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
package org.scalegraph.community;

import x10.compiler.Native;
import x10.compiler.NativeCPPInclude;
import x10.util.Team;
import x10.util.Random;

import org.scalegraph.Config;
import org.scalegraph.arpack.ARPACK;
import org.scalegraph.blas.BLAS;
import org.scalegraph.blas.DistDiagonalMatrix;
import org.scalegraph.blas.DistSparseMatrix;
import org.scalegraph.graph.Graph;
import org.scalegraph.util.Dist2D;
import org.scalegraph.util.DistMemoryChunk;
import org.scalegraph.util.MemoryChunk;
import org.scalegraph.util.MathAppend;
import org.scalegraph.util.Parallel;
import org.scalegraph.util.Team2;


@NativeCPPInclude("mpi.h")
final public class SpectralClusteringImpl {
	
	private def this() {}
	
	public static def run(g : Graph, attrName : String, numCluster : Int,
			tolerance : Double, maxitr : Int, threshold : Double): DistMemoryChunk[Int] {
		val config = Config.get();
		val team = config.worldTeam();
		val dist = config.dist2d();
		
		//Console.OUT.println(dist);
		//Console.OUT.println("vertices = " + g.numberOfVertices());
		//Console.OUT.println("edges    = " + g.numberOfEdges());
		
		val sw = new MyStopWatch();
		sw.start("create affinity matrix");
		
		val W = g.createDistSparseMatrix[Double](dist, attrName, false, false);
		val N = W.ids().numberOfLocalVertexes2N();
		val D = new DistMemoryChunk[Double](team.placeGroup(), () => new MemoryChunk[Double](N, (Long) => 1.0));
		BLAS.mult[Double](1.0, W, true, D, 0.0, D);
		team.placeGroup().broadcastFlat(() => {
			val vec_ = D();
			Parallel.iter(vec_.range(), (tid :Long, r :LongRange) => {
				for(i in r) vec_(i) = 1.0 / vec_(i);
			});
		});
		BLAS.mult[Double](1.0, DistDiagonalMatrix(D), W, true, 0.0, W);
		
		sw.next("calc eigenvectors");
		
		val params = new ARPACK.Params();
		params.nev = numCluster;
		params.tol = tolerance;
		params.rvec = 1;
		params.fit();
		val V = calcEigenVectors(team, W, params);
		
		sw.next("k-means");
		
		val result = kmeans(team, V, numCluster, maxitr, threshold);
		
		sw.end();
		sw.print();
		
		return result;
	}
	
	
	/*
	 * returns row-major dense matrix whose columns are nev eigenvectors
	 */
	private static def calcEigenVectors(team : Team, A : DistSparseMatrix[Double], params : ARPACK.Params) : DistMemoryChunk[Double] {
		
		assert(team.equals(Team.WORLD));  // current limitation
		
		val nloc_ = A.ids().numberOfLocalVertexes2N();
		val n_ = nloc_ * team.size();
		
		assert(n_ <= Int.MAX_VALUE);
		
		// global params for pdsaupd
		val n = n_ as Int;
		val nloc = nloc_ as Int;
		var comm_:Int = 0;
		@Native("c++", "comm_ = MPI_COMM_WORLD;") {}
		val comm = comm_;
		val nev:Int = params.nev;
		val bmat:Char = params.bmat;
		val which:Int = params.which;
		val tol:Double = params.tol;
		val ncv:Int = Math.min(params.ncv, n);
		val ldu:Int = nloc;
		val maxitr = params.maxitr;
		val lworkl:Int = params.lworkl;
		val x = new DistMemoryChunk[Double](team.placeGroup(), () => new MemoryChunk[Double](nloc));
		val y = new DistMemoryChunk[Double](team.placeGroup(), () => new MemoryChunk[Double](nloc));
		
		// global params for pdseupd
		val rvec:Int = params.rvec;
		val howmny:Char = params.howmny;
		val ldv:Int = nloc;
		val sigma:Double = params.sigma;
		
		return new DistMemoryChunk[Double](team.placeGroup(), () => {
			// local workspaces for pdsaupd
			val random = new Random(2L);
			val role = team.role()(0);
			var ido:Int = 0;
			val resid:Array[Double](1) = new Array[Double](nloc, (Int) => random.nextDouble());
			val u:Array[Double](1) = new Array[Double](ncv * ldu);
			val iparam:Array[Int](1) = new Array[Int](11);
			val ipntr:Array[Int](1) = new Array[Int](11);
			val workd:Array[Double](1) = new Array[Double](3 * nloc);
			val workl:Array[Double](1) = new Array[Double](lworkl);
			var info:Int = 1;
			
			// local workspaces for pdseupd
			val select:Array[Int](1) = new Array[Int](ncv);
			val d:Array[Double](1) = new Array[Double](nev);
			val v:Array[Double](1) = new Array[Double](nev * ldv);
			
			iparam(0) = 1;
			iparam(2) = maxitr;
			iparam(3) = 1;
			iparam(6) = 1;
			
			var iter:Int = 0;
			while(true) {
				//if(role == 0 && iter % 100 == 0) {
				//	Console.OUT.println("iter = " + iter);
				//}
				iter++;
				
				ARPACK.pdsaupd(comm, ido, bmat, nloc, which, nev, tol,
						resid, ncv, u, ldu, iparam, ipntr,
						workd, workl, lworkl, info);
				
				if(role == 0 && info != 0) {
					ARPACK.printError("pdsaupd", info);
				}
				
				if(ido == -1 || ido == 1) {
					// y <- OP(x)
					val x_ = new MemoryChunk[Double](workd.raw(), ipntr(0) - 1, nloc);
					val y_ = new MemoryChunk[Double](workd.raw(), ipntr(1) - 1, nloc);
					MemoryChunk.copy[Double](x_, 0L, x(), 0L, nloc);
					BLAS.mult_[Double](1.0, A, true, x, 0.0, y);
					MemoryChunk.copy[Double](y(), 0L, y_, 0L, nloc);
					
				} else if(ido == 2) {
					// y <- Bx
					Parallel.iter(0..(nloc-1), (tid:Int, r:IntRange) => {
						for(i in r) {
							workd(ipntr(1) - 1 + i) = workd(ipntr(0) - 1 + i);
						}
					});
				} else {
					if(role == 0 && ido != 99) Console.OUT.println("ARPACK: pdsaupd: unknown operation: ido = " + ido);
					break;
				}
			}
			
			if(role == 0) Console.OUT.println("ARPACK: iterations = " + iparam(2));
			if(role == 0) Console.OUT.println("converged Ritz values = " + iparam(4));
			
			if(iparam(4) < nev){
				if(role == 0) Console.OUT.println("ARPACK: pdsaupd: could not calculate all required Ritz values");
				//return Zero.get[DistMemoryChunk[Double]]();
			}
			
			ARPACK.pdseupd(comm, rvec, howmny, select, d, v, ldv,
					sigma, bmat, nloc, which, nev, tol, resid,
					ncv, u, ldu, iparam, ipntr, workd,
					workl, lworkl, info);
			
			if(role == 0){
				ARPACK.printError("pdseupd", info);
				Console.OUT.println(d);
			}
			
			val result = new MemoryChunk[Double](v.size);
			Parallel.iter(
					0..(nloc-1),
					(tid:Int, r:IntRange) => {
						for(i in r) {
							for(var j:Int = 0; j < nev; j++) {
								result(nev * i + j) = v(i + j * nloc);
							}
						}
					}
			);
			result
		});
	}
	
	/*
	 * It's better to implement Kmeans++ method.
	 */
	private static def kmeans(team : Team, dmc : DistMemoryChunk[Double], k : Int, maxitr : Int, threshold : Double) : DistMemoryChunk[Int] {
		assert(dmc().size() % k == 0L);
		val team2 = new Team2(team);
		val root = team.role()(0);
		val assign = new DistMemoryChunk[Int](team.placeGroup(), () => new MemoryChunk[Int](dmc().size() / k));
		val curC = new DistMemoryChunk[Double](team.placeGroup(), () => new MemoryChunk[Double](k * k));
		val nextC = new DistMemoryChunk[Double](team.placeGroup(), () => new MemoryChunk[Double](k * k));
		val count = new DistMemoryChunk[Long](team.placeGroup(), () => new MemoryChunk[Long](k));
		
		team2.placeGroup().broadcastFlat(() => {
			//Console.OUT.println(here + ": K-means started");
			
			val nloc = dmc().size() / k;
			val mc = dmc();
			val lassign = assign();
			val lcurC = curC();
			val lnextC = nextC();
			val lcount = count();
			
			// create initial centroids
			// if(team.role()(0) == 0) Console.OUT.println("create initial centroids");
			val r = new Random(2L);
			for(j in 0..(k-1)) {
				val i = r.nextLong(nloc);
				for(l in 0..(k-1)) {
					lnextC(j * k + l) = mc(i * k + l);
				}
				lcount(j)++;
			}
			
			for(itr in 1..maxitr) {
				if(team.role()(0) == 0) Console.OUT.println("itr = " + itr);
				
				// reduce centroids
				// if(team.role()(0) == 0) Console.OUT.println("reduce centroids");
				team2.allreduce(lnextC, lnextC, Team.ADD);
				team2.allreduce(lcount, lcount, Team.ADD);
				
				for(j in 0..(k-1)) {
					for(l in 0..(k-1)) {
						lnextC(j * k + l) /= lcount(j);
					}
				}
				
				// check convergence
				// if(team.role()(0) == 0) Console.OUT.println("check convergence");
				if(itr >= 2) {
					var converge:Boolean = true;
					for(j in 0..(k-1)) {
						var norm2:Double = 0.0;
						for(l in 0..(k-1)) {
							val x = lnextC(j * k + l) - lcurC(j * k + l);
							norm2 += x * x;
						}
						if(norm2 > threshold) {
							converge = false;
							break;
						}
					}
					if(converge) {
						if(team.role()(0) == 0) Console.OUT.println("k-means: iterations = " + itr);
						break;
					}
				}
				
				// move lnextC to lcurC, clear lnextC and lcount
				// if(team.role()(0) == 0) Console.OUT.println("move lnextC to lcurC, clear lnextC and lcount");
				for(j in 0..(k-1)) {
					for(l in 0..(k-1)) {
						lcurC(j * k + l) = lnextC(j * k + l);
						lnextC(j * k + l) = 0.0;
					}
					lcount(j) = 0L;
				}
				
				// assign vertices to the nearest cluster
				// if(team.role()(0) == 0) Console.OUT.println("assign vertices to the nearest cluster");
				for(i in 0..(nloc-1)) {
					var best:Int = -1;
					var bestNorm2:Double = Double.MAX_VALUE;
					for(j in 0..(k-1)) {
						var norm2:Double = 0.0;
						for(l in 0..(k-1)) {
							val x = mc(i * k + l) - lcurC(j * k + l);
							norm2 += x * x;
						}
						if(norm2 < bestNorm2) {
							best = j;
							bestNorm2 = norm2;
						}
					}
					lassign(i) = best;
					for(l in 0..(k-1)) {
						lnextC(best * k + l) += mc(i * k + l);
					}
					lcount(best)++;
				}
			}
			//Console.OUT.println(here + ": K-means finished");
		});
		
		return assign;
	}
	
}


class MyStopWatch {
	
	class Record {
		val label : String;
		var time : Long;
		
		def this(label : String, time : Long) {
			this.label = label;
			this.time =  time;
		}
	}
	
	val list : x10.util.ArrayList[Record] = new x10.util.ArrayList[Record]();
	var maxLength : Int = 0;
	
	def start(label : String) {
		list.add(new Record(label, x10.util.Timer.milliTime()));
		maxLength = Math.max(label.length(), maxLength);
		Console.OUT.println("*** " + label + " ***");
	}
	
	def next(label : String) {
		end();
		start(label);
	}
	
	def end() {
		val rec = list.getLast();
		rec.time = x10.util.Timer.milliTime() - rec.time;
	}
	
	def print() {
		for(rec in list) {
			val numTab = (maxLength / 8 + 1) - (rec.label.length() / 8);
			Console.OUT.printf("%s%s%.3f sec\n", rec.label, new String(new Array[Char](numTab, '\t')), rec.time / 1000.0);
		}
	}
}