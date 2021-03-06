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

package org.scalegraph.graph.id;

/**
 * ID Converter method collection for 1D row distributions.
 * 
 * V : Real Vertex ID
 * S : Source form ID
 * D : Destination form ID
 */
public final class OnedR {
	/** Vertex ID to Source ID Converter */
	public static final struct VtoS {
		val lgr :Int;
		val lgl :Int;
		val rmask :Long;
		
		public def this(ids :IdStruct) {
			lgr = ids.lgr;
			lgl = ids.lgl;
			rmask = ((1L << lgr) - 1L);
		}
		
		public operator this(id :Long) :Long = ((id & rmask) << lgl) | (id >> lgr);
	}

	/** Vertex ID to Destination ID Converter */
	public static final struct VtoD {
		val lgr :Int;
		
		public def this(ids :IdStruct) {
			lgr = ids.lgr;
		}
		
		public operator this(id :Long) :Long = (id >> lgr);
	}

	/** Source ID to Vertex ID Converter */
	public static final struct StoV {
		val lgr :Int;
		val lgl :Int;
		val lmask :Long;
		
		public def this(ids :IdStruct) {
			lgr = ids.lgr;
			lgl = ids.lgl;
			lmask = (1L << lgl) - 1L;
		}
		
		public operator this(id :Long) :Long = ((id & lmask) << lgr) | (id >> lgl);
	}

	/** Source ID to Destination ID Converter */
	public static final struct StoD {
		val lmask :Long;
		
		public def this(ids :IdStruct) {
			val lgl = ids.lgl;
			lmask = (1L << lgl) - 1L;
		}
		
		public operator this(id :Long) :Long = id & lmask;
	}

	/** Destination ID to Vertex ID Converter */
	public static final struct DtoV {
		val r :Int;
		val lgr :Int;
		
		public def this(ids :IdStruct, r :Int) {
			this.r = r;
			lgr = ids.lgr;
		}
		
		public operator this(id :Long) :Long = (id << lgr) | r;
	}

	/** Destination ID to Source ID Converter */
	public static final struct DtoS {
		val rshifted :Long;
		
		public def this(ids :IdStruct, r :Int) {
			val lgl = ids.lgl;
			rshifted = (r as Long) << lgl;
		}
		
		public operator this(id :Long) :Long = id | rshifted;
	}
}