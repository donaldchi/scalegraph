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

import x10.io.File;

import org.scalegraph.util.SString;
import org.scalegraph.io.FileReader;
import org.scalegraph.io.FileWriter;
import org.scalegraph.io.FileMode;

public abstract class FileNameProvider implements Iterable[SString] {
	protected val path : SString;
	public def this(path : SString) {
		this.path = path;
	}
	public abstract def isScattered() : Boolean;
	public abstract def fileName(index :Int) :SString;
	public def mkdir() {
		// default method assumes the path pointing to the normal file
		val last_sep = path.lastIndexOf(File.SEPARATOR);
		if(last_sep > 0) {
			(new File(path.substring(0, last_sep).toString())).mkdirs();
		}
	}
	public abstract def deleteFile() :void;
	public abstract def openRead(index :Int) :FileReader;
	public abstract def openWrite(index :Int) :FileWriter;
	
	// End of FileNameProvider definition //
	
	private class PathIterator implements Iterator[SString] {
		private var index :Int;
		public def this() { index = 0; }
		public def hasNext() = new File(fileName(index).toString()).exists();
		public def next() = fileName(index++);
	}

	private static class SingleFileNameProvider extends FileNameProvider {
		public def this(path : SString) {
			super(path);
		}
		public def isScattered() = false;
		public def fileName(index :Int) = path;
		public def deleteFile() {
			(new File(path.toString())).delete();
		}
		public def openRead(index :Int) = new FileReader(path);
		public def openWrite(index :Int) = new FileWriter(path, FileMode.Create);
		
		public def iterator() = new PathIterator() {
			public def hasNext() = (index == 0);
		};
	}

	private static class NumberScatteredFileNameProvider extends FileNameProvider {
		public def this(path : SString) {
			super(path);
		}
		public def isScattered() = true;
		public def fileName(index :Int) = SString.format(path, index);
		public def deleteFile() {
			var index :Int = 0;
			do {
				val file = new File(fileName(index).toString());
				if (!file.exists()) break;
				file.delete();
			} while(true);
		}
		public def openRead(index :Int) = new FileReader(fileName(index));
		public def openWrite(index :Int) = new FileWriter(fileName(index), FileMode.Create);
		public def iterator() = new PathIterator();
		
	}

	private static class DirectoryScatteredFileNameProvider extends FileNameProvider {
		public def this(path : SString) {
			super(path);
		}
		public def isScattered() = true;
		public def fileName(index :Int) = SString.format("%s/part-%05d" as SString, path, index);
		public def mkdir() {
			(new File(path.toString())).mkdirs();
		}
		public def deleteFile() {
			val dir = new File(path.toString());
			for(i in 0..(dir.list().size-1)) {
				new File(fileName(i).toString()).delete();
			}
		}
		public def openRead(index :Int) = new FileReader(fileName(index));
		public def openWrite(index :Int) = new FileWriter(fileName(index), FileMode.Create);
		public def iterator() = new PathIterator();
		
	}
	
	/**
	 * Creates appropriate file manager instance.
	 * @param path filename passed by user
	 * @param scattered hint to choose file manager
	 */
	private static def create(path :SString, isRead :Boolean, scattered :Boolean) {
		val num_pos = path.indexOf("%d");
		if(num_pos != -1) {
			val last_sep = path.lastIndexOf(File.SEPARATOR);
			if(last_sep > num_pos) {
				throw new IllegalArgumentException("Number position may not be on a directory name.");
			}
			return new NumberScatteredFileNameProvider(path);
		}
		if(isRead) {
			if(new File(path.toString()).isFile()) {
				return new SingleFileNameProvider(path);
			}
			return new DirectoryScatteredFileNameProvider(path);
		}
		else {
			if(scattered) {
				return new DirectoryScatteredFileNameProvider(path);
			}
			return new SingleFileNameProvider(path);
		}
	}
	
	/**
	 * Creates appropriate file manager instance.
	 * @param path filename passed by user
	 * @param scattered hint to choose file manager
	 */
	public static def createForRead(path :SString)
			= create(path, true, false);
	
	/**
	 * Creates appropriate file manager instance.
	 * @param path filename passed by user
	 * @param scattered hint to choose file manager
	 */
	public static def createForWrite(path :SString, scattered :Boolean)
			= create(path, false, scattered);
}
