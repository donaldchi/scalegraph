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
package org.scalegraph.io.impl;

import org.scalegraph.util.MemoryPointer;
import org.scalegraph.util.MemoryChunk;
import org.scalegraph.util.GrowableMemory;
import org.scalegraph.util.DistMemoryChunk;

import x10.compiler.NativeCPPCompilationUnit;
import x10.compiler.NativeCPPOutputFile;
import x10.compiler.NativeCPPInclude;
import x10.compiler.NativeRep;
import x10.compiler.Native;
import x10.util.Team;
import org.scalegraph.io.ID;


@NativeCPPInclude("CSVHelper.h")
public abstract class CSVAttributeHandler {
	@Native("c++", "org::scalegraph::io::impl::H_CHUNK_SIZE")
	public static val H_CHUNK_SIZE :Long = 256;
	
	public val typeId :Int;
	public val doubleQuoated :Boolean;
	
	public def this(typeId :Int, doubleQuoated :Boolean) {
		this.typeId = typeId;
		this.doubleQuoated = doubleQuoated;
	}
	
	public def isSkip() :Boolean = false;
	public def typeId() :Int = typeId;
	public abstract def createBlockGrowableMemory() :Any;
	public abstract def parseElements(elemPtrs :MemoryChunk[MemoryPointer[Byte]], outBuf :Any) :void;
	public abstract def mergeResult(team :Team, nthreads :Int, getBuffer :(tid :Int) => Any) :Any;
	public abstract def print(team :Team, dmc : Any) : void;
	
	// End of CSVAttributeHandler definition //
	
	private static class PrimitiveHandler[T] extends CSVAttributeHandler {
		public def this(typeId :Int, doubleQuoated :Boolean) { super(typeId, doubleQuoated); }
		
		@Native("c++", "org::scalegraph::io::impl::CSVParseElements<#T >(#elemPtrs. #outBuf)")
		private static native def nativeParseElements[T](
				elemPtrs :MemoryChunk[MemoryPointer[Byte]], outBuf :GrowableMemory[T]) :void;

		public def createBlockGrowableMemory() = new GrowableMemory[T]();
		
		public def parseElements(elemPtrs :MemoryChunk[MemoryPointer[Byte]], outBuf :Any) {
			val typedOutBuf = outBuf as GrowableMemory[T];
			nativeParseElements[T](elemPtrs, typedOutBuf);
		}
		public def mergeResult(team :Team, nthreads :Int, getBuffer :(tid :Int) => Any) :Any {
			val ret = DistMemoryChunk.make[T](team.placeGroup(), ()=> {
				var totalSize :Long = 0;
				// compute the size
				for(tid in 0..(nthreads-1)) {
					val buf = getBuffer(tid) as GrowableMemory[T];
					totalSize += buf.size();
				}
				val outbuf = new MemoryChunk[T](totalSize);
				// copy the result
				var offset :Long = 0;
				for(tid in 0..(nthreads-1)) {
					val buf = getBuffer(tid) as GrowableMemory[T];
					MemoryChunk.copy(buf.raw(), 0l, outbuf, offset, buf.size());
					offset += buf.size();
				}
				assert (offset == totalSize);
				return outbuf;
			});
			return ret;
		}
		
		public def print(team :Team, any : Any) {
			val dmc = any as DistMemoryChunk[T];
			for(var i:Int = 0; i < team.size(); i++) at(team.places()(i)) {
				Console.OUT.print(dmc() + " ");
			}
			Console.OUT.println("");
		}
		
	}
	
	private static class StringHandler extends PrimitiveHandler[String] {
		public def this(typeId :Int, doubleQuoated :Boolean) { super(typeId, doubleQuoated); }
		
		@Native("c++", "org::scalegraph::io::impl::CSVParseStringElements(#elemPtrs. #outBuf)")
		private static native def nativeParseElements(
				elemPtrs :MemoryChunk[MemoryPointer[Byte]], outBuf :GrowableMemory[String]) :void;
		
		public def parseElements(elemPtrs :MemoryChunk[MemoryPointer[Byte]], outBuf :Any) {
			val typedOutBuf = outBuf as GrowableMemory[String];
			nativeParseElements(elemPtrs, typedOutBuf);
		}
	}
	
	private static class SkipHandler extends CSVAttributeHandler {
		public def this(typeId :Int, doubleQuoated :Boolean) { super(typeId, doubleQuoated); }
		public def createBlockGrowableMemory() = null;
		public def isSkip() = true;
		public def parseElements(elemPtrs :MemoryChunk[MemoryPointer[Byte]], outBuf :Any) :void { }
		public def mergeResult(team :Team, nthreads :Int, getBuffer :(tid :Int) => Any) :Any {
			throw new IllegalOperationException("Type NULL Handler does not contain any data.");
		}
		public def print(team :Team, any : Any) {
			throw new IllegalOperationException("Type NULL Handler does not contain any data.");
		}
	}
	
	public static def create(typeId :Int, doubleQuoated :Boolean) :CSVAttributeHandler {
		switch(typeId) {
		case ID.TYPE_NONE:
			return new SkipHandler(typeId, doubleQuoated);
		case ID.TYPE_BOOLEAN:
			return new PrimitiveHandler[Boolean](typeId, doubleQuoated);
		case ID.TYPE_BYTE:
			return new PrimitiveHandler[Byte](typeId, doubleQuoated);
		case ID.TYPE_SHORT:
			return new PrimitiveHandler[Short](typeId, doubleQuoated);
		case ID.TYPE_INT:
			return new PrimitiveHandler[Int](typeId, doubleQuoated);
		case ID.TYPE_LONG:
			return new PrimitiveHandler[Long](typeId, doubleQuoated);
		case ID.TYPE_FLOAT:
			return new PrimitiveHandler[Float](typeId, doubleQuoated);
		case ID.TYPE_DOUBLE:
			return new PrimitiveHandler[Double](typeId, doubleQuoated);
		case ID.TYPE_UBYTE:
			return new PrimitiveHandler[UByte](typeId, doubleQuoated);
		case ID.TYPE_USHORT:
			return new PrimitiveHandler[UShort](typeId, doubleQuoated);
		case ID.TYPE_UINT:
			return new PrimitiveHandler[UInt](typeId, doubleQuoated);
		case ID.TYPE_ULONG:
			return new PrimitiveHandler[ULong](typeId, doubleQuoated);
		case ID.TYPE_CHAR:
			return new PrimitiveHandler[Char](typeId, doubleQuoated);
		case ID.TYPE_STRING:
			return new StringHandler(typeId, doubleQuoated);
		default:
			throw new IllegalArgumentException("invalid data type");
		}
	}
}


