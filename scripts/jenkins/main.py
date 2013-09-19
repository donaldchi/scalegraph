#!/bin/env python3
import helper
from helper import *
import helper
import os
from optparse import OptionParser
import TAP

DEBUG=False

## mpirunを実行するスクリプト
##
##

#-------------------------------------------------#
#ModuleName    = "TeamBenchmark"
#TestFileDir   = os.environ["HOME"]+"/Develop/ScaleGraph/src"
TestWorkDir   = os.environ["prefix"]
SrcDir= os.path.abspath(os.path.dirname(__file__))+"/../../src"


#-------------------------------------------------#
##引数を設定.-hオプションでhelpが見られる
## --mpi {MPI} mpich,mvapich,openmpiのいずれかを指定
## -t {TESTCASE} でテストケースの指定.デフォルトは TESTCASE=small
#-------parser_begin--------#

def main():
    usage = "Usage: # runTest {TESTCASE}"
    parser = OptionParser(usage=usage)
    parser.add_option("-t","--test",action="store",default="small",
                    type="string",
                    help="Test case to run",dest="testcase")
    parser.add_option("-n",action="store",default="4",
                      type="int",
                      help="number of nodes",dest="maxNode")
    parser.add_option("--mpi",action="store",
                    default="mvapich",type="string",
                    dest="mpi",help="mpi to run tests",
                    metavar="MPI")
    parser.add_option("--yamlDir",action="store",dest="yamlDir",
                    default="./tests",
                    metavar="yamlDir")
    parser.add_option("--x10dir",action="store",dest="x10Dir",
                    default="../../src/test",
                    help="Test file directory")
    parser.add_option("--workspace",action="store",dest="workspace",
                    default=TestWorkDir,
                    help="directory to build and to run test")
    parser.add_option("--source",action="store",
                      dest="srcDir",default=SrcDir)
    (opts,args) = parser.parse_args()
###-------parser_end-------------

    workingDir = opts.workspace

    if(DEBUG):
        helper.printOpts(opts,args)
    
##yamlからの設定の読み込み

#各ファイルのビルド、テストの実行
    if(DEBUG):
        print(opts.yamlDir+"/*.yaml is loaded")
    yamlFiles = os.listdir( opts.yamlDir )
    if(DEBUG):
        print(yamlFiles)
    helper.initTap(len(yamlFiles))
    
    for filename in yamlFiles:
        filePref, ext = os.path.splitext(filename)
        if ext != ".yaml":
            continue
        
        sandbox    = workingDir+"/"+filePref

        initDir(sandbox)
        #print("load yamlfile:"+filename)
        attributes = helper.loadFromYaml(
            opts.yamlDir+"/"+filename,
            testcase=opts.testcase)
    
        for attribute in attributes:
            attribute["node"] = opts.maxNode
            
            buildresult = build_test(filePref,
                        opts.x10Dir+"/"+filePref+".x10",
                        sandbox,
                        opts.srcDir) 
            if buildresult == 0:
                run_test(name=filePref,
                binName=filePref,
                workPath=sandbox,
                mpi=opts.mpi,
                attributes=attribute)
            else:
                fail_run_test(name = filePref,
                        binName=filePref,
                        workPath=sandbox,
                        attributes=attribute,
                        describe="build failed")
                pass
    
    if(DEBUG):
        print("DEBUG: Testcase attributes:" + str(attribute))

if __name__ == '__main__':
    main()
