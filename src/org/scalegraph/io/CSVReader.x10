/*
 *  This file is part of the ScaleGraph project (https://sites.google.com/site/scalegraph/).
 *
 *  This file is licensed to You under the Eclipse Public License (EPL);
 *  You may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *      http://www.opensource.org/licenses/eclipse-1.0.php
 *
 *  (C) Copyright ScaleGraph Team 2011-2012.
 */
package org.scalegraph.io;

import org.scalegraph.util.SString;
import org.scalegraph.util.MemoryChunk;
import org.scalegraph.util.MemoryPointer;
import org.scalegraph.util.GrowableMemory;
import org.scalegraph.io.impl.FileNameProvider;
import org.scalegraph.io.impl.InputSplitter;
import org.scalegraph.io.impl.CSVAttributeHandler;
import org.scalegraph.io.impl.DoubleQuoatedCSVSplitter;
import org.scalegraph.io.impl.LineBreakSplitter;

import x10.compiler.NativeCPPCompilationUnit;
import x10.compiler.NativeCPPOutputFile;
import x10.compiler.NativeCPPInclude;
import x10.compiler.NativeRep;
import x10.compiler.Native;
import x10.io.File;
import x10.util.Team;
import x10.io.IOException;

@NativeCPPCompilationUnit("CSVHelper.cc") 
public class CSVReader {

	@NativeCPPInclude("CSVHelper.h")
	@NativeCPPOutputFile("CSVAttribute.h")
	@NativeRep("c++", "org::scalegraph::io::impl::NativeCSVAttribute*",
			"org::scalegraph::io::impl::NativeCSVAttribute*", null)
	private static struct CSVAttribute {
		@Native("c++", "(x10_boolean) (#this)->includeType")
		public native def includeType() :Boolean;
		@Native("c++", "(x10_boolean) (#this)->doubleQuoated")
		public native def doubleQuoated() :Boolean;
		@Native("c++", "(#this)->name")
		public native def name() :SString;
		@Native("c++", "(#this)->typeName")
		public native def attTypeName() :SString;
	}
	
	@NativeCPPInclude("CSVHelper.h")
	@NativeCPPOutputFile("NativeCSVHeader.h")
	@NativeRep("c++", "org::scalegraph::io::impl::NativeCSVHeader*",
			"org::scalegraph::io::impl::NativeCSVHeader*", null)
   private static struct NativeCSVHeader {
		@Native("c++", "org::scalegraph::io::impl::readCSVHeader(#headerLine)")
		public static native def make(headerLine :SString) : NativeCSVHeader;
		@Native("c++", "(#this)->~NativeCSVHeader(); x10aux::dealloc(#this)")
		public native def del() :void;

		@Native("c++", "(x10_int) (#this)->attrs.size()")
		public native def size() :Int;
		@Native("c++", "&((#this)->attrs[#index])")
		public native def attribute(index :Int) : CSVAttribute;
	}
	
	private static class ReaderBuffer {
		public val attHandler :Array[CSVAttributeHandler];
		public val buffer :Array[Any];
		public val elemPtrs :MemoryChunk[MemoryPointer[Byte]];
		public val chunkSize :GrowableMemory[Long];
		public val stride :Long;
		public val numElems :Int;
		public var lines :Int;
		
		public def this(attHandler :Array[CSVAttributeHandler]) {
			this.attHandler = attHandler;
			this.numElems = attHandler.size;
			this.stride = CSVAttributeHandler.H_CHUNK_SIZE;
			this.buffer = new Array[Any](numElems,
					(i :Int) => attHandler(i).createBlockGrowableMemory());
			this.elemPtrs = new MemoryChunk[MemoryPointer[Byte]](stride * numElems);
			this.chunkSize = new GrowableMemory[Long]();
		}

		public native def nativeParseChunk(data :MemoryChunk[Byte]) :Long;
		
		public def parse(data :MemoryChunk[Byte]) {
			val data_size = data.size();
			var data_off :Long = 0;
			var totalLines :Long = 0;
			while(data_off < data_size) {
				data_off += nativeParseChunk(data.subpart(data_off, data.size() - data_off));
				totalLines += lines;
				for(e in 0..(numElems-1)) {
					attHandler(e).parseElements(elemPtrs.subpart(e*stride, lines), buffer(e));
				}
			}
			// store the number of lines for merging all data later
			chunkSize.add(totalLines);
		}
	}
	
	
	/*
	 * Tree types of chunks:
	 * P_CHUNK: The input file is split into P_CHUNK at first. Each P_CHUNK is assigned to a place. Each InputSplit represent one P_CHUNK.
	 * S_CHUNK:
	 * T_CHUNK: Each P_CHUNK is split into T_CHUNK. Each T_CHUNK is assigned to a thread.
	 * H_CHUNK: Each P_CHUNK is split into H_CHUNK. Attribute handlers can process H_CHUNK at once.
	 */
	
	public static def read(team :Team, path :SString, columnDef :Array[Int], includeHeader :Boolean) {
		//
		val nthreads = Runtime.NTHREADS;
		val numColumns = columnDef.size;
		val columnNames = new Array[SString](numColumns);
		val attHandler = new Array[CSVAttributeHandler](columnDef.size);

		val fman = FileNameProvider.createForRead(path);
		var includeDQ :Boolean = false;
		var dataOffset :Long = 0;
		
		// read header and create attribute handler
		{
			val reader = new FileReader(fman.fileName(0));
			val headerLine = reader.fastReadLine();
			
			if(includeHeader) {
				val header = NativeCSVHeader.make(headerLine);
				if(columnDef.size > header.size()) {
					header.del();
					reader.close();
					throw new IOException("The file does not contain enough attributes.");
				}
				dataOffset = reader.currentOffset();
				
				for([i] in attHandler) {
					val att = header.attribute(i);
					val typeId = att.includeType() 
							? ID.typeId(att.attTypeName().toString())
							: columnDef(i);
					columnNames(i) = att.name();
					attHandler(i) = CSVAttributeHandler.create(typeId, att.doubleQuoated());
					if(att.doubleQuoated()) includeDQ = true;
				}
				
				header.del();
			}
			else {
				includeDQ = (headerLine.trim().bytes()(0) as Char == '"');
				for([i] in attHandler) {
					val typeId = columnDef(i);
					columnNames(i) = SString.format("column-%d" as SString, i);
					attHandler(i) = CSVAttributeHandler.create(typeId, includeDQ);
				}
			}
			
			reader.close();
		}

		// broadcast attribute handlers
		val bufferPLH = PlaceLocalHandle.makeFlat[Array[ReaderBuffer]](team.placeGroup(),
				() => new Array[ReaderBuffer](nthreads, (i:Int) => new ReaderBuffer(attHandler)));
		
		val splitter = includeDQ ? new DoubleQuoatedCSVSplitter() : new LineBreakSplitter();
		
		// read data
		splitter.split(team, fman, dataOffset, nthreads,
			(tid :Int, data :MemoryChunk[Byte]) => { bufferPLH()(tid).parse(data); });
		
		var enabledColumns :Int = 0;
		for(e in 0..(numColumns-1)) {
			if(!attHandler(e).isSkip()) ++enabledColumns;
		}
		
		// merge result
		val attributes = new Array[Any](enabledColumns);
		val attrNames = new Array[String](enabledColumns);
		val attrIds = new Array[Int](enabledColumns);
		var attrIndex :Int = 0;
		for(e in 0..(numColumns-1)) {
			attributes(attrIndex) = attHandler(e).mergeResult(team,
					(tid :Int) => bufferPLH()(tid).buffer(e));
			attrNames(attrIndex) = columnNames(e).toString();
			attrIds(attrIndex) = attHandler(e).typeId();
		}

		return new NamedDistData(attrNames, attrIds, attributes, null);
	}
}
