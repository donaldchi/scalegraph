package org.scalegraph.graph;

import x10.util.ArrayList;
import x10.util.GrowableIndexedMemoryChunk;
import x10.util.HashMap;
import x10.util.concurrent.AtomicLong;
import x10.util.Team;
import x10.util.Timer;

import x10.compiler.Pinned;
import x10.compiler.Pragma;
import x10.compiler.Inline;

import org.scalegraph.concurrent.Parallel;
import org.scalegraph.concurrent.ScatterGather;
import org.scalegraph.util.Debug;
import org.scalegraph.util.GrowableMemory;
import org.scalegraph.util.MemoryChunk;
import org.scalegraph.util.DistMemoryChunk;

/** Vertex ID translator. The purpose of this class is assigning the small integer number for each vertex.
 * The instances of this class are pinned to a particular place because moving the instance to another place is not worth.
 */
@Pinned public class VertexTranslator[T] {
	
	static val debug = true;
	private @Inline static def debugln (str:String) : void {
		if (debug) {
			Console.OUT.println("" + Timer.milliTime() + ":VertexTranslator: " + here + "(" + Runtime.workerId() + ")" + str);
			Console.OUT.flush();
		}
	}

	private count = new AtomicLong(0);
	private team : Team;
	private teamRank: Int;
	private teamSize: Int;
	private hashFunc: (T)=>Int;
	private table = new HashMap[T, Long]();
	private vertexNames :GrowableMemory[T];
	private var maxLocalId : Int = 0;

	/** Creates vertex translator.
	 * @param team The same team with the graph.
	 * @param vertexNames This object builds vertex ID mapping to the growable memory. 
	 * In the most case, vertexNames is the backing storage for the name attribute of the graph.
	 */
	public def this(team__:Team, vertexNames__ :GrowableMemory[T]){
		this(team__, vertexNames__, (x:T)=>x.hashCode());
	}
	
	/** Creates vertex translator.
	 * @param team The same team with the graph.
	 * @param vertexNames This object builds vertex ID mapping to the growable memory. 
	 * In the most case, vertexNames is the backing storage for the name attribute of the graph.
	 * @param hashFunc Hashing function for distributing vertex IDs.
	 */
	public def this(team__:Team, vertexNames__ :GrowableMemory[T], hashFunc__:(T)=>Int){
		hashFunc = hashFunc__;
		team = team__;
		teamRank = team.getRole(here);
		teamSize = team.size();
		vertexNames = vertexNames__;
	}
	
	/** Returns the local table size.
	 */
	public def size() = table.size();
	
	private def countToId(count:Long) {
		return count * teamSize + teamRank;
	}
	
	private def putLocalAndTranslate(vertices: MemoryChunk[T], translated :MemoryChunk[Long]) {
		//		val count_origin = count.getAndAdd(vertices.size);
		
		// TODO: parallelize
		// TODO: manage the hash bias due to the place distribution
		// 1. create hashmap for adding elements only in parallel
		// 2. numbering adding elements
		// 3. consolidate hashmaps
		// 4. create translations
		
		for (i in vertices.range()) {
			val key = vertices(i);
			if (table.containsKey(key)) {
				translated(i) = table.getOrThrow(key);
			} else {
				val count = count.getAndAdd(1);
				val id = countToId(count);
				table.put(key, id);
				vertexNames.add(key);
				assert (((vertexNames.size() - 1) as Long) == count);
			}
		}
		return translated;
	}
	
	private def putLocal(vertices: MemoryChunk[T]) {
		//		val count_origin = count.getAndAdd(vertices.size);
		for (i in vertices.range()) {
			val key = vertices(i);
			val count = count.getAndAdd(vertices.size());
			val id = countToId(count);
			table.put(key, id);
			vertexNames.add(key);
			assert (vertexNames.size() as Long == count);
		}
	}
	
	private def translateLocal(vertices: MemoryChunk[T], translated :MemoryChunk[Long]) {
		try {
			Parallel.iter(vertices.range(), (i:Long)=> {
				translated(i) = table.getOrThrow(vertices(i));
			});
		}
		catch (e :x10.util.NoSuchElementException) {
			Console.OUT.println("Invalid vertex ID");
		//	e.printStackTrace();
			throw e;
		}
	}
	
	private def innerPutWithAllAndTranslate(scatterGather :ScatterGather,
			edges: MemoryChunk[T], translated: MemoryChunk[Long], withPut :Boolean) {
		val sizeMask = teamSize - 1;
		Parallel.iter(edges.range(), (tid: Long, r :LongRange)=> {
			val counts = scatterGather.getCounts(tid as Int);
			for(i in r)
				counts(hashFunc(edges(i)) & sizeMask) += 1;
		});
		scatterGather.sum();
		val partitioned = new MemoryChunk[T](edges.size());
		val indexes = new MemoryChunk[Int](edges.size());
		Parallel.iter(edges.range(), (tid: Long, r :LongRange)=> {
			val offsets = scatterGather.getOffsets(tid as Int);
			for(i in r) {
				val e = edges(i);
				val idx = offsets( hashFunc(e) & sizeMask )++;
				indexes(i) = idx;
				partitioned(idx) = e;
			}
		});
		val remoteData = scatterGather.scatter(partitioned);
		val remoteTranslated = new MemoryChunk[Long](remoteData.size());
		
		if(withPut)
			putLocalAndTranslate(remoteData, remoteTranslated);
		else
			translateLocal(remoteData, remoteTranslated);
		
		val recvTranslated = new MemoryChunk[Long](edges.size());
		scatterGather.gather(remoteTranslated, recvTranslated);
		Parallel.iter(edges.range(), (tid: Long, r :LongRange)=> {
			for(i in r)
				translated(i) = recvTranslated(indexes(i));
		});
	}
	
	/** Translates vertex IDs. All place of the team must call this method in parallel.
	 * @param edges The vertices which will be translated
	 * @param translated The storage for translated edge list
	 * @param withPut true: Assigning new number, false: only translation
	 */
	public def translateWithAll(edges: MemoryChunk[T], translated :MemoryChunk[Long], withPut :Boolean) {
		val CHUNK_SIZE = 1L << 23;
		val iterations = team.allreduce(teamRank,
				(edges.size() + CHUNK_SIZE - 1) / CHUNK_SIZE, Team.MAX);
		
		Debug.println(toString(), "edges: " + edges + ", kinds: " +  teamSize + "iterations: " + iterations);
		
		val scatterGather = new ScatterGather(team);
		val edgesDist = edges.distributor();
		val translatedDist = translated.distributor();
		for(it in 0..(iterations-1)) {
			val size = Math.min(CHUNK_SIZE, edgesDist.remain());
			innerPutWithAllAndTranslate(scatterGather,
					edgesDist.next(size), translatedDist.next(size), withPut);
		}
		edgesDist.checkFinish();
		translatedDist.checkFinish();
	}
	
	/** Translates vertex IDs.
	 * @param translator Translator object
	 * @param vertices The vertices which will be translated
	 * @param translated The storage for translated edge list
	 * @param withPut true: Assigning new number, false: only translation
	 */
	public static def translate[T](translator :PlaceLocalHandle[VertexTranslator[T]],
			vertices :DistMemoryChunk[T], translated :DistMemoryChunk[Long], withPut :Boolean)
	{
		@Pragma(Pragma.FINISH_SPMD) finish for(p in translator().team.placeGroup()) at (p) async {
			translator().translateWithAll(vertices(), translated(), withPut);
		}
	}
	
	private static def translate[T](translator :PlaceLocalHandle[VertexTranslator[T]],
			vertices :DistMemoryChunk[T], withPut :Boolean) :DistMemoryChunk[Long]
	= new DistMemoryChunk[Long](translator().team.placeGroup(), ()=> {
			val translated = new MemoryChunk[Long](vertices().size());
			translator().translateWithAll(vertices(), translated, withPut);
			return translated;
		});
	
	/** Translates vertex IDs without assigning new vertex number.
	 * @returns A DistMemoryChunk that contains translated vertex IDs.
	 * @param translator Translator object
	 * @param vertices The vertices which will be translated
	 */
	public static def translate[T](translator :PlaceLocalHandle[VertexTranslator[T]],
			vertices :DistMemoryChunk[T]) :DistMemoryChunk[Long]
	= translate[T](translator, vertices, false);
	
	/** Translates vertex IDs with assigning new vertex number.
	 * @returns A DistMemoryChunk that contains translated vertex IDs.
	 * @param translator Translator object
	 * @param vertices The vertices which will be translated
	 */
	public static def putAndTranslate[T](translator :PlaceLocalHandle[VertexTranslator[T]],
			vertices :DistMemoryChunk[T]) :DistMemoryChunk[Long]
	= translate[T](translator, vertices, true);
}
