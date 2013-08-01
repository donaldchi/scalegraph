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
package org.scalegraph.util;

import x10.compiler.Native;
import x10.compiler.NativeCPPInclude;
import x10.compiler.NativeCPPCompilationUnit;
import x10.compiler.NativeCPPOutputFile;

@NativeCPPInclude("StringHelper.h")
@NativeCPPOutputFile("SString__TokenIterator.h")
@NativeCPPCompilationUnit("StringHelper.cc")

public class SStringBuilder {
	private var buffer :GrowableMemory[Byte] = new GrowableMemory[Byte]();
	
	public def this() { }
	
	public def this(str :SString) {
		buffer.setMemory(str.bytes());
	}
	
	// TODO:
	public native def add[T](x :T) :SStringBuilder;

	// TODO:
	public native def add[T1](fmt :SString, o1 :T1) :SStringBuilder;
	public native def add[T1,T2](fmt :SString, o1 :T1, o2 :T2) :SStringBuilder;
	public native def add[T1,T2,T3](fmt :SString, o1 :T1, o2 :T2, o3 :T3) :SStringBuilder;
	public native def add[T1,T2,T3,T4](fmt :SString, o1 :T1, o2 :T2, o3 :T3, o4 :T4) :SStringBuilder;
	public native def add[T1,T2,T3,T4,T5](fmt :SString, o1 :T1, o2 :T2, o3 :T3, o4 :T4, o5 :T5) :SStringBuilder;
	public native def add[T1,T2,T3,T4,T5,T6](fmt :SString, o1 :T1, o2 :T2, o3 :T3, o4 :T4, o5 :T5, o6 :T6) :SStringBuilder;
	
	public def capacity() = buffer.capacity();
	
	public def delete(start :Int, end :Int) {
		val buf_size = buffer.size();
		if(start > end) throw new IllegalArgumentException("start > end");
		if(end > buf_size) throw new IllegalArgumentException("end > size()");
		MemoryChunk.copy(buffer.raw(), end as Long, 
				buffer.raw(), start as Long, buf_size - end);
		buffer.setSize(buf_size - end + start);
	}
	
	public def grow(minCapacity :Int) :void { buffer.grow(minCapacity); }
	
	public def indexOf(str :SString) = indexOf(str, 0);

	// TODO:
	public native def indexOf(str :SString, from :Int) :Int;
	
	public def lastIndexOf(str :SString) = lastIndexOf(str, 0);

	// TODO:
	public native def lastIndexOf(str :SString, from :Int) :Int;
	
	public def result() = SString(buffer.raw().subpart(0, size()));
	
	public def replace(start :Int, end :Int, str :SString) {
		val buf_size = buffer.size();
		if(start > end) throw new IllegalArgumentException("start > end");
		if(end > buf_size) throw new IllegalArgumentException("end > size()");
		val str_size = str.size();
		val new_size = start + buf_size - end + str_size;
		buffer.setSize(new_size);
		MemoryChunk.copy(buffer.raw(), start as Long, buffer.raw(), end as Long, buf_size - start);
		buffer.setSize(new_size);
	}
	
	public def reverse() {
		// TODO:
		var left :Int = 0;
		val right :Int = buffer.size() as Int - 1;
		val buf = buffer.raw();
		while(left < right) { // swap byte
			val tmp = buf(left);
			buf(left) = buf(right);
			buf(right) = tmp;
		}
	}
	
	public def size() = buffer.size();
	
	public def substring(start :Int) = substring(start, 0);
	
	public def substring(start :Int, end :Int) = SString(buffer.raw().subpart(start, end));
	
	public def toString() = result().toString();
	
	public def trimToSize() {
		buffer.shrink(0);
	}
}
