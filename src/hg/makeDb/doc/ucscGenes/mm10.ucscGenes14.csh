#!/bin/tcsh -efx
# :vim nowrap
# for emacs: -*- mode: sh; -*-
# This describes how to make the UCSC genes on mm10, though
# hopefully by editing the variables that follow immediately
# this will work on other databases too.


#
# Prerequisites
# Before executing this script, rebuild the swissprot and proteins databases.


# Directories
set genomes = /hive/data/genomes
set dir = $genomes/mm10/bed/ucsc.13.2
set scratchDir = /hive/scratch
set testingDir = $scratchDir/ucscGenes

# Databases
set db = mm10
set Db = Mm10
set oldDb = mm9
set xdb = hg19
set Xdb = Hg19
set ydb = canFam3
set zdb = rn4
set spDb = sp140122
#set pbDb = proteins111004
set ratDb = rn4
set RatDb = Rn4
set fishDb = danRer7
set flyDb = dm3
set wormDb = ce6
set yeastDb = sacCer3

# The net alignment for the closely-related species indicated in $xdb
set xdbNetDir = $genomes/$db/bed/lastz.${xdb}/axtChain

# Blast tables
set rnBlastTab = rnBlastTab
if ($db =~ hg* ) then
    set blastTab = hgBlastTab
    set xBlastTab = mmBlastTab
endif
if ($db =~ mm* ) then
    set blastTab = mmBlastTab
    set xBlastTab = hgBlastTab
endif

# If rebuilding on an existing assembly make tempDb some bogus name like tmpFoo2, otherwise 
# make tempDb same as db.
#set tempPrefix = "tmp"
#set tmpSuffix = "Foo13"
#set tempDb = ${tempPrefix}${tmpSuffix}
#set bioCycTempDb = tmpBioCyc${tmpSuffix}
set tempDb = mm10


# Table for SNPs
#set snpTable = snp130

# Public version number
set lastVer = 5
set curVer = 6

# Database to rebuild visiGene text from.  Should include recent mouse and human
# but not the one you're rebuilding if you're rebuilding. (Use tempDb instead).
set vgTextDbs = (mm8 mm9 hg18 hg19 $tempDb)

# Proteins in various species
set tempFa = $dir/ucscGenes.faa
set xdbFa = $genomes/$xdb/bed/ucsc.13/ucscGenes.faa
set ratFa = $genomes/$ratDb/bed/blastpRgdGene2/rgdGene2Pep.faa
set fishFa = $genomes/$fishDb/bed/blastp/ensembl.faa
set flyFa = $genomes/$flyDb/bed/hgNearBlastp/100806/$flyDb.flyBasePep.faa
set wormFa = $genomes/$wormDb/bed/blastp/wormPep190.faa
set yeastFa = $genomes/$yeastDb/bed/sgdAnnotations/blastTab/sacCer3.sgd.faa

# Other files needed
set bioCycPathways = /hive/data/outside/bioCyc/120801/1.7/data/pathways.col
set bioCycGenes = /hive/data/outside/bioCyc/120801/1.7/data/genes.col
set rfam = /hive/data/outside/Rfam/111130


# Tracks
set multiz = multiz60way

# NCBI Taxon 10090 for mouse, 9606 for human
set taxon = 10090

# Previous gene set
#set oldGeneDir = $genomes/hg19/bed/ucsc.12
#set oldGeneBed = $oldGeneDir/ucscGenes.bed
set oldGeneBed = /dev/null

# Machines
set dbHost = hgwdev
set ramFarm = encodek
set cpuFarm = swarm

# Code base
set kent = ~/kent

# Create initial dir
#set scriptDir = `pwd`
mkdir -p $dir
cd $dir

# Get Genbank info
txGenbankData $db
# creates the files:
#	mgcStatus.tab  mrna.psl  refPep.fa  refSeq.psl
#	mrna.fa        mrna.ra   refSeq.fa  refSeq.ra


# process RA Files
txReadRa mrna.ra refSeq.ra .
# creates the files:
#	cds.tab             refSeqStatus.tab	mrnaSize.tab	refToPep.tab
#	refPepStatus.tab    exceptions.tab	accVer.tab

# Get some other info from the database.  Best to get it about
# the same time so it is synced with other data. Takes 4 seconds.
hgsql -N $db -e 'select distinct name,sizePolyA from mrnaOrientInfo' | \
	subColumn -miss=sizePolyA.miss 1 stdin accVer.tab sizePolyA.tab
#	creates the files:
#	sizePolyA.miss  sizePolyA.tab

# Get CCDS for human (or else just an empty file)
if ($db =~ hg* && \
  `hgsql -N $db -e "show tables;" | grep -E -c "ccdsGene|chromInfo"` == 2) then
    hgsql -N $db -e "select name,chrom,strand,txStart,txEnd,cdsStart,cdsEnd,exonCount,exonStarts,exonEnds from ccdsGene" | genePredToBed > ccds.bed
    hgsql -N $db \
	-e "select mrnaAcc,ccds from ccdsInfo where srcDb='N'" > refToCcds.tab
else
    echo -n "" > ccds.bed
    echo -n "" > refToCcds.tab
endif



# Get tRNA for human (or else just an empty file)
if ($db =~ hg* && \
  `hgsql -N $db -e "show tables;" | grep -E -c "tRNAs|chromInfo"` == 2) then
    hgsql -N $db -e "select chrom,chromStart,chromEnd,name,score,strand,chromStart,chromEnd,"0","1",chromEnd-chromStart,"0" from tRNAs" > trna.bed 
    bedToPsl $genomes/$db/chrom.sizes trna.bed trna.psl
else
    echo -n "" > trna.bed
    echo -n "" > trna.psl
    echo -n "" > refToCcds.tab
endif


# Get the blocks in this genome that are syntenic to the $xdb genome
netFilter -syn $xdbNetDir/${db}.${xdb}.net.gz > ${db}.${xdb}.syn.net
netToBed -maxGap=0 ${db}.${xdb}.syn.net ${db}.${xdb}.syn.bed


#if  # didn't do thie

# Get the Rfams that overlap with blocks that are syntenic to $Xdb, and filter out
# any duplicate Rfam blocks.  In some cases, where there are two related Rfam models,
# the same genomic region can get two distinct hits.  For our purposes, we only
# want one of those hits, because we're looking for regions that might be genes and
# don't care as much about the subclass of gene.
cat ${rfam}/${db}/Rfam.bed |sort -k1,1 -k2,2n > rfam.sorted.bed
bedRemoveOverlap rfam.sorted.bed rfam.distinctHits.bed
bedIntersect -aHitAny rfam.distinctHits.bed ${db}.${xdb}.syn.bed rfam.syntenic.bed


bedToPsl $genomes/$db/chrom.sizes rfam.syntenic.bed rfam.syntenic.psl
#else
touch rfam.syntenic.psl
touch  rfam.syntenic.bed
#endif # didn't do thie
e


# Create directories full of alignments split by chromosome.
mkdir -p est refSeq mrna 
pslSplitOnTarget refSeq.psl refSeq
pslSplitOnTarget mrna.psl mrna
bedSplitOnChrom ccds.bed ccds

foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    if (! -e refSeq/$c.psl) then
	  echo creating empty refSeq/$c.psl
          echo -n "" >refSeq/$c.psl
    endif
    if (! -e mrna/$c.psl) then
	  echo creating empty mrna/$c.psl
          echo -n "" >mrna/$c.psl
    endif
    hgGetAnn -noMatchOk $db intronEst $c est/$c.psl
    if (! -e est/$c.psl) then
	  echo creating empty est/$c.psl
          echo -n "" >est/$c.psl
    endif
    if (! -e ccds/$c.bed) then
	  echo creating empty ccds/$c.bed
          echo -n "" >ccds/$c.bed
    endif
end


# Get list of accessions that are associated with antibodies from database.
# This will be a good list but not 100% complete.  Cluster these to get
# four or five antibody heavy regions.  Later we'll weed out input that
# falls primarily in these regions, and, include the regions themselves
# as special genes.  Takes 40 seconds
txAbFragFind $db antibodyAccs
pslCat mrna/*.psl -nohead | fgrep -w -f antibodyAccs > antibody.psl
clusterPsl -prefix=ab.ab.antibody. antibody.psl antibody.cluster
if ($db =~ mm*) then
    echo chr12 > abChrom.lst
    echo chr16 >> abChrom.lst
    echo chr6 >> abChrom.lst
    fgrep -w -f abChrom.lst antibody.cluster | cut -f 1-12 | bedOrBlocks stdin antibody.bed
else
    awk '$13 > 100' antibody.cluster | cut -f 1-12 > antibody.bed
endif


# Convert psls to bed, saving mapping info and weeding antibodies.  Takes 2.5 min
foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    if (-s refSeq/$c.psl) then
	txPslToBed refSeq/$c.psl -noFixStrand -cds=cds.tab $genomes/$db/$db.2bit refSeq/$c.bed -unusual=refSeq/$c.unusual
    else
	echo "creating empty refSeq/$c.bed"
	touch refSeq/$c.bed
    endif
    if (-s mrna/$c.psl) then
	txPslToBed mrna/$c.psl -cds=cds.tab $genomes/$db/$db.2bit \
		stdout -unusual=mrna/$c.unusual \
	    | bedWeedOverlapping antibody.bed maxOverlap=0.5 stdin mrna/$c.bed
    else
	echo "creating empty mrna/$c.bed"
	touch mrna/$c.bed
    endif
    if (-s est/$c.psl) then
	txPslToBed est/$c.psl $genomes/$db/$db.2bit stdout \
	    | bedWeedOverlapping antibody.bed maxOverlap=0.3 stdin est/$c.bed
    else
	echo "creating empty est/$c.bed"
	touch est/$c.bed
    endif
end

#  seven minutes to this point


# Create mrna splicing graphs.  Takes 10 seconds.
mkdir -p bedToGraph
foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    txBedToGraph -prefix=$c. ccds/$c.bed ccds refSeq/$c.bed refSeq mrna/$c.bed mrna  \
	bedToGraph/$c.txg
end

# Create est splicing graphs.  Takes 6 minutes.
foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    txBedToGraph -prefix=e$c. est/$c.bed est est/$c.txg
end


# Create an evidence weight file
cat > trim.weights <<end
refSeq  100
ccds    50
mrna    2
txOrtho 1
exoniphy 1
est 1
end



# Make evidence file for EST graph edges supported by at least 2 
# ests.  Takes about 30 seconds.
foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    txgGoodEdges est/$c.txg  trim.weights 2 est est/$c.edges
end


# Setup other species dir
mkdir -p $dir/$xdb
cd $dir/$xdb

# Get other species mrna including ESTs.  Takes about three minutes
mkdir -p refSeq mrna est
foreach c (`awk '{print $1;}' $genomes/$xdb/chrom.sizes`)
    echo $c
    hgGetAnn -noMatchOk $xdb refSeqAli $c stdout | txPslToBed stdin $genomes/$xdb/$xdb.2bit refSeq/$c.bed 
    hgGetAnn -noMatchOk $xdb mrna $c stdout | txPslToBed stdin $genomes/$xdb/$xdb.2bit mrna/$c.bed
    hgGetAnn -noMatchOk $xdb intronEst $c stdout | txPslToBed stdin $genomes/$xdb/$xdb.2bit est/$c.bed
end


# Create other species splicing graphs.  Takes about five minutes.
cd $dir/$xdb
rm -f other.txg
foreach c (`awk '{print $1;}' $genomes/$xdb/chrom.sizes`)
    echo $c
    txBedToGraph refSeq/$c.bed refSeq mrna/$c.bed mrna est/$c.bed est stdout >> other.txg
end


# Clean up all but final other.txg
rm -r est mrna refSeq



# Unpack chains and nets, apply synteny filter and split by chromosome
# Takes 5 minutes.  Make up phony empty nets for ones that are empty after
# synteny filter.
cd $dir/$xdb
chainSplit chains $genomes/$db/bed/lastz.$xdb/axtChain/$db.$xdb.all.chain.gz
netFilter -syn $genomes/$db/bed/lastz.$xdb/axtChain/$db.$xdb.net.gz \
	| netSplit stdin nets
cd nets
foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    if (! -e $c.net) then
        echo -n >  $c.net
    endif
end

cd ../chains
foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    if (! -e $c.chain) then
        echo  -n >  $c.chain
    endif
end

# Make txOrtho directory and a para spec file
cd $dir
mkdir -p txOrtho/edges
cd txOrtho
echo '#LOOP' > template
echo './runTxOrtho $(path1) '"$xdb $db" >> template
echo '#ENDLOOP' >> template
    
cat << '_EOF_' > runTxOrtho
#!/bin/csh -ef
set inAgx = ../bedToGraph/$1.txg
set inChain = ../$2/chains/$1.chain
set inNet = ../$2/nets/$1.net
set otherTxg = ../$2/other.txg
set tmpDir = /scratch/tmp/$3
set workDir = $tmpDir/${1}_${2}
mkdir -p $tmpDir
mkdir -p $workDir
txOrtho $inAgx $inChain $inNet $otherTxg $workDir/$1.edges
mv $workDir/$1.edges edges/$1.edges
rmdir $workDir
rmdir --ignore-fail-on-non-empty $tmpDir
'_EOF_'
    #	<< happy emacs
    chmod +x runTxOrtho
    touch toDoList
cd $dir/bedToGraph
foreach f (*.txg)
    set c=$f:r
    if ( -s $f ) then
	echo $c >> ../txOrtho/toDoList
    else
	echo "warning creating empty $c.edges result"
	touch ../txOrtho/edges/$c.edges
    endif
end
cd ..



# Do txOrtho parasol run on iServer (high RAM) cluster
ssh $ramFarm "cd $dir/txOrtho; gensub2 toDoList single template jobList"
ssh $ramFarm "cd $dir/txOrtho; para make jobList"
ssh $ramFarm "cd $dir/txOrtho; para time > run.time"
cat txOrtho/run.time

# Completed: 46 of 46 jobs
# CPU time in finished jobs:       1473s      24.55m     0.41h    0.02d  0.000 y
# IO & Wait Time:                  1751s      29.18m     0.49h    0.02d  0.000 y
# Average job time:                  70s       1.17m     0.02h    0.00d
# Longest finished job:             152s       2.53m     0.04h    0.00d
# Submission to last job:       5254726s   87578.77m  1459.65h   60.82d

# Filter out some duplicate edges. These are legitimate from txOrtho's point
# of view, since they represent two different mouse edges both supporting
# a human edge. However, from the human point of view we want only one
# support from mouse orthology.  Just takes a second.
#  TODO: assuming true is mouse is target.
cd $dir/txOrtho
mkdir -p uniqEdges
foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    cut -f 1-9 edges/$c.edges | sort | uniq > uniqEdges/$c.edges
end
cd ..


#
# testing suggestion: uncomment below
# mkdir -p $testingDir
# compareModifiedFileSizes.csh $oldGeneDir .
# cut -f-3,5,6,8 txOrtho/uniqEdges/chr22.edges >$testingDir/chr22.subset.edges.new
# cut -f-3,5,6,8 $oldGeneDir/txOrtho/uniqEdges/chr22.edges \
#    >$testingDir/chr22.subset.edges.old
# checkRandomLinesExist.py -s $testingDir/chr22.subset.edges.old \
#    -d $testingDir/chr22.subset.edges.new

# Clean up chains and nets since they are big
cd $dir
rm -r $xdb/chains $xdb/nets


# Get exonophy. Takes about 4 seconds.
hgsql -N $db -e "select chrom, txStart, txEnd, name, "1", strand from exoniphy order by chrom, txStart;" \
    > exoniphy.bed
bedToTxEdges exoniphy.bed exoniphy.edges



# Add evidence from ests, orthologous other species transcripts, and exoniphy
# Takes 36 seconds.
mkdir -p graphWithEvidence
foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    echo adding evidence for $c
    if ( -s bedToGraph/$c.txg ) then
    txgAddEvidence -chrom=$c bedToGraph/$c.txg exoniphy.edges exoniphy stdout \
	   | txgAddEvidence stdin txOrtho/uniqEdges/$c.edges txOrtho stdout \
	   | txgAddEvidence stdin est/$c.edges est graphWithEvidence/$c.txg
    else
	touch graphWithEvidence/$c.txg
    endif
end


#
# special testing suggestion: uncomment below
# compareModifiedFileSizes.csh $oldGeneDir .
# cut -f1-3,5 graphWithEvidence/chr22.txg > $testingDir/chr22.graph.bounds.new
# cut -f1-3,5 $oldGeneDir/graphWithEvidence/chr22.txg > $testingDir/chr22.graph.bounds.old
# checkRandomLinesExist.py -s $testingDir/chr22.graph.bounds.old \
#  -d $testingDir/chr22.graph.bounds.new
#



# Do  txWalk  - takes 32 seconds (mostly loading the mrnaSize.tab again and
# again...)
mkdir -p txWalk
if ($db =~ mm*) then
    set sef = 0.6
else
    set sef = 0.75
endif
foreach c (`awk '{print $1;}' $genomes/$db/chrom.sizes`)
    txWalk graphWithEvidence/$c.txg trim.weights 3 txWalk/$c.bed \
	-evidence=txWalk/$c.ev -sizes=mrnaSize.tab -defrag=0.25 \
	    -singleExonFactor=$sef
end


# Make a file that lists the various categories of alt-splicing we see.
# Do this by making and analysing splicing graphs of just the transcripts
# that have passed our process so far.  The txgAnalyze program occassionally
# will make a duplicate, which is the reason for the sort/uniq run.
# Takes 7 seconds.
cat txWalk/*.bed > txWalk.bed
txBedToGraph txWalk.bed txWalk txWalk.txg
txgAnalyze txWalk.txg $genomes/$db/$db.2bit stdout | sort | uniq > altSplice.bed



# Get txWalk transcript sequences.  This'll take about an hour
#  twoBitToFa $genomes/$db/$db.2bit -bed=txWalk/$c.bed stdout >> txWalk.fa
    # sequenceForBed -db=$db -bedIn=txWalk/$c.bed -fastaOut=stdout -upCase -keepName >> txWalk.fa
rm -f txWalk.fa
twoBitToFa $genomes/$db/$db.2bit -bed=txWalk.bed txWalk.fa
rm -rf txFaSplit
mkdir -p txFaSplit
faSplit sequence txWalk.fa 200 txFaSplit/


#
# A good time for testing.  Uncomment the lines (not all at once) to 
# compare the line count for files just built in the current version
# and the previous version
#
# compareModifiedFileSizes.csh $oldGeneDir .
# # Check that most of the old alt events are still there
# checkRandomLinesExist.py -d $oldGeneDir/altSplice.bed -s ./altSplice.bed
# # check that most of the old txWalk bed entries overlap some new entry
# bedIntersect -aHitAny txWalk.bed $oldGeneDir/txWalk.bed \
#    $testingDir/txWalk.intersect.bed
# wc $testingDir/txWalk.intersect.bed
#

# Fetch human protein set and table that describes if curated or not.
# Takes about a minute
hgsql -N $spDb -e \
  "select p.acc, p.val from protein p, accToTaxon x where x.taxon=$taxon and p.acc=x.acc" \
  | awk '{print ">" $1;print $2}' >uniProt.fa
hgsql -N $spDb -e "select i.acc,i.isCurated from info i,accToTaxon x where x.taxon=$taxon and i.acc=x.acc" > uniCurated.tab

#TODO: remove these odd comments
# echo "continuing after first kki job"
# echo "preparing $cpuFarm job"

mkdir -p blat/rna/raw
echo '#LOOP' > blat/rna/template
echo './runTxBlats $(path1) '"$db"' $(root1) {check out line+ raw/ref_$(root1).psl}' >> blat/rna/template
echo '#ENDLOOP' >> blat/rna/template
 
cat << '_EOF_' > blat/rna/runTxBlats
#!/bin/csh -ef
set ooc = /scratch/data/$2/$2.11.ooc
set target = ../../txFaSplit/$1
set out1 = raw/mrna_$3.psl
set out2 = raw/ref_$3.psl
set tmpDir = /scratch/tmp/$2/ucscGenes/rna
set workDir = $tmpDir/$3
mkdir -p $tmpDir
mkdir $workDir
blat -ooc=$ooc -minIdentity=95 $target ../../mrna.fa $workDir/mrna_$3.psl
blat -ooc=$ooc -minIdentity=97 $target ../../refSeq.fa $workDir/ref_$3.psl
mv $workDir/mrna_$3.psl raw/mrna_$3.psl
mv $workDir/ref_$3.psl raw/ref_$3.psl
rmdir $workDir
rmdir --ignore-fail-on-non-empty $tmpDir
'_EOF_'
    #	<< happy emacs
chmod +x blat/rna/runTxBlats
cd txFaSplit
ls -1 *.fa > ../blat/rna/toDoList
cd ..

ssh $cpuFarm "cd $dir/blat/rna; gensub2 toDoList single template jobList"
ssh $cpuFarm "cd $dir/blat/rna; para make jobList"

ssh $cpuFarm "cd $dir/blat/rna; para time > run.time"
# Completed: 197 of 197 jobs
# CPU time in finished jobs:      25076s     417.94m     6.97h    0.29d  0.001 y
# IO & Wait Time:                  9292s     154.86m     2.58h    0.11d  0.000 y
# Average job time:                 174s       2.91m     0.05h    0.00d
# Longest finished job:             483s       8.05m     0.13h    0.01d
# Submission to last job:          1884s      31.40m     0.52h    0.02d
# Estimated complete:                 0s       0.00m     0.00h    0.00d

# Set up blat jobs for proteins vs. translated txWalk transcripts
cd $dir
mkdir -p blat/protein/raw
echo '#LOOP' > blat/protein/template
echo './runTxBlats $(path1) '"$db"' $(root1) {check out line+ raw/ref_$(root1).psl}' >> blat/protein/template
echo '#ENDLOOP' >> blat/protein/template

cat << '_EOF_' > blat/protein/runTxBlats
#!/bin/csh -ef
set ooc = /scratch/data/$2/$2.11.ooc
set target = ../../txFaSplit/$1
set out1 = uni_$3.psl
set out2 = ref_$3.psl
set tmpDir = /scratch/tmp/$2/ucscGenes/prot
set workDir = $tmpDir/$3
mkdir -p $tmpDir
mkdir $workDir
blat -t=dnax -q=prot -minIdentity=90 $target ../../uniProt.fa $workDir/$out1
blat -t=dnax -q=prot -minIdentity=90 $target ../../refPep.fa $workDir/$out2
mv $workDir/$out1 raw/$out1
mv $workDir/$out2 raw/$out2
rmdir $workDir
rmdir --ignore-fail-on-non-empty $tmpDir
'_EOF_'
    #	<< happy emacs
chmod +x blat/protein/runTxBlats
cd txFaSplit
ls -1 *.fa > ../blat/protein/toDoList
cd ..

# Run protein/transcript blat job on cluster
ssh $cpuFarm "cd $dir/blat/protein; gensub2 toDoList single template jobList"

ssh $cpuFarm "cd $dir/blat/protein; para make jobList"
ssh $cpuFarm "cd $dir/blat/protein; para time > run.time"

cat blat/protein/run.time
# Completed: 197 of 197 jobs
# CPU time in finished jobs:      19711s     328.51m     5.48h    0.23d  0.001 y
# IO & Wait Time:                 11799s     196.66m     3.28h    0.14d  0.000 y
# Average job time:                 160s       2.67m     0.04h    0.00d
# Longest finished job:             531s       8.85m     0.15h    0.01d
# Submission to last job:           871s      14.52m     0.24h    0.01d

# Sort and select best alignments. Remove raw files for space. Takes  a couple
# of hours. Use pslReps not pslCdnaFilter because need -noIntrons flag,
# and also working on protein as well as rna alignments. The thresholds
# for the proteins in particular are quite loose, which is ok because
# they will be weighted against each other.  We lose some of the refSeq
# mappings at tighter thresholds.
cd $dir/blat
pslCat -nohead rna/raw/ref*.psl | sort -k 10 | \
	pslReps -noIntrons -nohead -minAli=0.90 -nearTop=0.005 stdin rna/refSeq.psl /dev/null
pslCat -nohead rna/raw/mrna*.psl | sort -k 10 | \
	pslReps -noIntrons -nohead -minAli=0.90 -nearTop=0.005  stdin rna/mrna.psl /dev/null
pslCat -nohead protein/raw/ref*.psl | sort -k 10 | \
	pslReps -noIntrons -nohead -nearTop=0.02  -ignoreSize -minAli=0.85 stdin protein/refSeq.psl /dev/null
pslCat -nohead protein/raw/uni*.psl | sort -k 10 | \
	pslReps -noIntrons -nohead -nearTop=0.02  -minAli=0.85 stdin protein/uniProt.psl /dev/null
rm -r protein/raw

# use this if(0) statement to control section of script to run
#	Look for the BRACKET word to find the corresponding endif and exit
cd $dir

# Get parts of multiple alignments corresponding to transcripts.
# Takes a couple of hours.  Could do this is a small cluster job
# to speed it up.
echo $db $xdb $ydb $zdb > ourOrgs.txt
foreach c (`cut -f1 $genomes/$db/chrom.sizes`)
    echo "doing chrom $c"
    if (-s txWalk/$c.bed ) then
	mafFrags $db $multiz txWalk/$c.bed stdout -bed12 -meFirst \
	   | mafSpeciesSubset stdin ourOrgs.txt txWalk/$c.maf -keepFirst
    endif
end


cd $dir

# Create and populate directory with various CDS evidence
mkdir -p cdsEvidence
cat txWalk/*.maf | txCdsPredict txWalk.fa -nmd=txWalk.bed -maf=stdin cdsEvidence/txCdsPredict.tce
txCdsEvFromRna refSeq.fa cds.tab blat/rna/refSeq.psl txWalk.fa \
	cdsEvidence/refSeqTx.tce -refStatus=refSeqStatus.tab \
	-unmapped=cdsEvidence/refSeqTx.unmapped -exceptions=exceptions.tab
txCdsEvFromRna mrna.fa cds.tab blat/rna/mrna.psl txWalk.fa \
	cdsEvidence/mrnaTx.tce -mgcStatus=mgcStatus.tab \
	-unmapped=cdsEvidence/mrna.unmapped
txCdsEvFromProtein refPep.fa blat/protein/refSeq.psl txWalk.fa \
	cdsEvidence/refSeqProt.tce -refStatus=refPepStatus.tab \
	-unmapped=cdsEvidence/refSeqProt.unmapped \
	-exceptions=exceptions.tab -refToPep=refToPep.tab \
	-dodgeStop=3 -minCoverage=0.3
txCdsEvFromProtein uniProt.fa blat/protein/uniProt.psl txWalk.fa \
	cdsEvidence/uniProt.tce -uniStatus=uniCurated.tab \
	-unmapped=cdsEvidence/uniProt.unmapped -source=trembl


txCdsEvFromBed ccds.bed ccds txWalk.bed ../../$db.2bit cdsEvidence/ccds.tce
cat cdsEvidence/*.tce | sort  > unweighted.tce

# Merge back in antibodies, and add the small, noncoding genes that shouldn't go 
# through txWalk because their gene boundaries should not change much.  Before
# adding them, weed out anything that overlaps a txWalk transcript to avoid 
# getting duplicate transcripts.

bedWeedOverlapping txWalk.bed rfam.syntenic.bed rfam.weeded.bed

bedWeedOverlapping txWalk.bed trna.bed trna.weeded.bed
cat txWalk.bed antibody.bed trna.weeded.bed rfam.weeded.bed > abWalk.bed
sequenceForBed -db=$db -bedIn=antibody.bed -fastaOut=stdout -upCase -keepName > antibody.fa
sequenceForBed -db=$db -bedIn=trna.weeded.bed -fastaOut=stdout -upCase -keepName \
  > trna.weeded.fa
sequenceForBed -db=$db -bedIn=rfam.weeded.bed -fastaOut=stdout -upCase -keepName \
  > rfam.weeded.fa
cat txWalk.fa antibody.fa trna.weeded.fa rfam.weeded.fa > abWalk.fa


# Pick ORFs, make genes
cat refToPep.tab refToCcds.tab | \
        txCdsPick abWalk.bed unweighted.tce stdin pick.tce pick.picks \
	-exceptionsIn=exceptions.tab \
	-exceptionsOut=abWalk.exceptions 
txCdsToGene abWalk.bed abWalk.fa pick.tce pick.gtf pick.fa \
	-bedOut=pick.bed -exceptions=abWalk.exceptions
# Create gene info table. Takes 8 seconds
cat mrna/*.unusual refSeq/*.unusual | awk '$5=="flip" {print $6;}' > all.flip
cat mrna/*.psl refSeq/*.psl trna.psl rfam.syntenic.psl \
      | txInfoAssemble pick.bed pick.tce cdsEvidence/txCdsPredict.tce \
	altSplice.bed abWalk.exceptions sizePolyA.tab stdin all.flip prelim.info

# Cluster purely based on CDS (in same frame). Takes 1 second
txCdsCluster pick.bed pick.cluster


# Flag suspicious CDS regions, and add this to info file. Weed out bad CDS.
# Map CDS to gene set.  Takes 10 seconds.  Might want to reconsider using
# txCdsWeed here.
txCdsSuspect pick.bed txWalk.txg pick.cluster prelim.info pick.suspect pick.info 
txCdsWeed pick.tce pick.info weededCds.tce weededCds.info
txCdsToGene abWalk.bed abWalk.fa weededCds.tce weededCds.gtf weededCds.faa \
	-bedOut=weededCds.bed -exceptions=abWalk.exceptions \
	-tweaked=weededCds.tweaked

# After txCdsToGene, the transcripts in weededCds.bed might be
# slightly different from those in abWalk.bed.  Make a new sequence
# file, weeded.fa, to replace abWalk.fa.

sequenceForBed -db=$db -bedIn=weededCds.bed -fastaOut=weeded.fa \
    -upCase -keepName



# Separate out transcripts into coding and 4 uncoding categories.
# Generate new gene set that weeds out the junkiest. Takes 9 seconds.
txGeneSeparateNoncoding weededCds.bed weededCds.info \
	coding.bed nearCoding.bed nearCodingJunk.bed antisense.bed uncoding.bed separated.info
# coding 35031, codingJunk 8955, nearCoding 3941, junk 4045, antisense 1082, noncoding 10112

awk '$2 != "nearCodingJunk"' separated.info > weeded.info
awk '$2 == "nearCodingJunk" {print $1}' separated.info > weeds.lst
cat coding.bed nearCoding.bed antisense.bed uncoding.bed | sort -k1,1 -k2,3n >weeded.bed

# Make up a little alignment file for the ones that got tweaked.
sed -r 's/.*NM_//' weededCds.tweaked | awk '{printf("NM_%s\n", $1);}' > tweakedNm.lst
fgrep -f tweakedNm.lst refToPep.tab | cut -f 2 > tweakedNp.lst
fgrep -f weededCds.tweaked weededCds.bed > tweakedNm.bed
sequenceForBed -db=$db -bedIn=tweakedNm.bed -fastaOut=tweakedNm.fa -upCase -keepName
faSomeRecords refPep.fa tweakedNp.lst tweakedNp.fa
blat -q=prot -t=dnax -noHead tweakedNm.fa tweakedNp.fa stdout | sort -k 10 > tweaked.psl

# Make an alignment file for refSeqs that swaps in the tweaked ones
weedLines weededCds.tweaked blat/protein/refSeq.psl refTweaked.psl
cat tweaked.psl >> refTweaked.psl

# Make precursor to kgProtMap table.  This is a psl file that maps just the CDS of the gene
# to the genome.
txGeneCdsMap weeded.bed weeded.info pick.picks refTweaked.psl \
	refToPep.tab $genomes/$db/chrom.sizes cdsToRna.psl \
	rnaToGenome.psl
pslMap cdsToRna.psl rnaToGenome.psl cdsToGenome.psl

# map mm9 knownGene to mm10
cd $dir
set lift = "/gbdb/$oldDb/liftOver/${oldDb}To${Db}.over.chain.gz"
genePredToFakePsl $oldDb knownGene $oldDb.kg.psl $oldDb.kg.cds

# only keep those id's that uniquely map to mm10
zcat $lift | pslMap -chainMapFile -swapMap $oldDb.kg.psl stdin stdout | pslCDnaFilter -uniqueMapped stdin stdout |  sort -k 14,14 -k 16,16n | pslToBed -cds=$oldDb.kg.cds stdin $oldDb.$db.kg.bed 

#     drop nonUnique:     112     285

#TODO:  figure out better wayto deal with txLastId
set oldGeneBed=$oldDb.$db.kg.bed
txGeneAccession $oldGeneBed ~kent/src/hg/txGene/txGeneAccession/txLastId \
	weeded.bed txToAcc.tab oldToNew.tab

tawk '{print $4}' oldToNew.tab | sort | uniq -c
#   5108 compatible
#  48739 exact
#   1460 lost
#   5274 new

echo "select * from knownGene" | hgsql mm9 | sort > mm9.knownGene.gp
grep lost oldToNew.tab | awk '{print $2}' | sort > lost.txt
join lost.txt mm9.knownGene.gp > mm9.lost.gp

awk '{if ($7 == $6) print}' mm9.lost.gp | wc -l
# non-coding 762
awk '{if ($7 != $6) print}' mm9.lost.gp | wc -l
# coding 698

# Assign permanent accessions to each transcript, and make up a number
# of our files with this accession in place of the temporary IDs we've been
# using.  Takes 4 seconds

cd $dir
txGeneAccession $oldGeneBed ~kent/src/hg/txGene/txGeneAccession/txLastId \
	weeded.bed txToAcc.tab oldToNew.tab
subColumn 4 weeded.bed txToAcc.tab ucscGenes.bed
subColumn 1 weeded.info txToAcc.tab ucscGenes.info
weedLines weeds.lst pick.picks stdout | subColumn 1 stdin txToAcc.tab ucscBadUniprot.picks
subColumn 4 coding.bed txToAcc.tab ucscCoding.bed
subColumn 4 nearCoding.bed txToAcc.tab ucscNearCoding.bed
subColumn 4 antisense.bed txToAcc.tab ucscAntisense.bed
subColumn 4 uncoding.bed txToAcc.tab ucscUncoding.bed
subColumn 10 cdsToGenome.psl txToAcc.tab ucscProtMap.psl
cat txWalk/*.ev | weedLines weeds.lst stdin stdout | subColumn 1 stdin txToAcc.tab ucscGenes.ev


# Make files with (a) representative protein and mrna accessions, and (b) the protein
# and mrna sequences representing direct transcription/translation of the bed blocks.  
# The reresentative proteins and mrnas will be taken from RefSeq for the RefSeq ones, 
# and derived from our transcripts for the rest.
# Load these sequences into database. Takes 17 seconds.
txGeneProtAndRna weeded.bed weeded.info weeded.fa weededCds.faa \
    refSeq.fa refToPep.tab refPep.fa txToAcc.tab ucscGenes.fa ucscGenes.faa \
    ucscGenesTx.fa ucscGenesTx.faa

# Generate ucscGene/uniprot blat run.
mkdir -p $dir/blat/uniprotVsUcsc
cd $dir/blat/uniprotVsUcsc
mkdir -p raw
mkdir -p ucscFaaSplit
faSplit sequence ../../ucscGenes.faa 100 ucscFaaSplit/uc
ls -1 ucscFaaSplit/uc*.fa > toDoList

echo '#LOOP' > template
echo './runBlats $(path1) '"$db"' $(root1) {check out line+ raw/uni_$(root1).psl}' >> template
echo '#ENDLOOP' >> template

cat << '_EOF_' > runBlats
#!/bin/csh -ef
set out1 = uni_$3.psl
set tmpDir = /scratch/tmp/$2/ucscGenes/uniprotVsUcsc
set workDir = $tmpDir/$3
mkdir -p $tmpDir
mkdir $workDir
blat -prot -minIdentity=90 $1 ../../uniProt.fa $workDir/$out1
mv $workDir/$out1 raw/$out1
rmdir $workDir
rmdir --ignore-fail-on-non-empty $tmpDir
'_EOF_'
    #	<< happy emacs
chmod +x runBlats

gensub2 toDoList single template jobList

# Run protein/transcript blat job on cluster
ssh $cpuFarm "cd $dir/blat/uniprotVsUcsc; para make jobList"
ssh $cpuFarm "cd $dir/blat/uniprotVsUcsc; para time > run.time"

cat run.time
# Completed: 97 of 97 jobs
# CPU time in finished jobs:       1167s      19.45m     0.32h    0.01d  0.000 y
# IO & Wait Time:                   405s       6.75m     0.11h    0.00d  0.000 y
# Average job time:                  16s       0.27m     0.00h    0.00d
# Longest finished job:              60s       1.00m     0.02h    0.00d
# Submission to last job:            62s       1.03m     0.02h    0.00d

pslCat raw/*.psl > ../../ucscVsUniprot.psl
rm -r raw


# Fixup UniProt links in picks file.  This is a little circuitious.  In the future may
# avoid using the picks file for the protein link, and rely on protein/protein blat
# to do the assignment.  The current use of the uniProt protein/ucscGenes mrna alignments
# and the whole trip through evidence and picks files is largely historical from when
# there was a different CDS selection process.
cd $dir
txCdsRedoUniprotPicks ucscBadUniprot.picks ucscVsUniprot.psl uniCurated.tab ucscGenes.picks



# Cluster the coding and the uncoding sets, and make up canonical and
# isoforms tables. Takes 3 seconds.
txCdsCluster ucscCoding.bed coding.cluster
txBedToGraph ucscUncoding.bed uncoding uncoding.txg -prefix=non
txBedToGraph ucscAntisense.bed antisense antisense.txg -prefix=anti
cat uncoding.txg antisense.txg > senseAnti.txg
txGeneCanonical coding.cluster ucscGenes.info senseAnti.txg ucscGenes.bed ucscNearCoding.bed \
	canonical.tab isoforms.tab txCluster.tab

# Make up final splicing graph just containing our genes, and final alt splice
# table.
txBedToGraph ucscGenes.bed ucscGenes ucscGenes.txg
txgAnalyze ucscGenes.txg $genomes/$db/$db.2bit stdout | sort | uniq > ucscSplice.bed


#####################################################################################
# Now the gene set is built.  Time to start loading it into the database,
# and generating all the many tables that go on top of known Genes.
# We do this initially in a temporary database.

# Protect databases from overwriting

if ( $tempDb =~ "${tempPrefix}*" ) then
    if ( 2 == `hgsql -N -e "show databases;" mysql | grep -E -c -e "$tempDb|"'^mysql$'` ) then
	echo "tempDb: '$tempDb' already exists, it should not"
	exit 255
    else
	echo "creating tempDb: '$tempDb'"
	# Create temporary database with a few small tables from main database
	hgsqladmin create $tempDb
	hgsqldump $db chromInfo | hgsql $tempDb
	hgsqldump $db trackDb_$user | hgsql $tempDb
    endif
else
    echo "tempDb does not match $tempPrefix"
    hgsql -N $tempDb -e "show tables;" | grep -E -c "chromInfo|trackDb_$user"
    if (2 != `hgsql -N $tempDb -e "show tables;" | grep -E -c "chromInfo|trackDb_$user"` ) then
	echo "do not find tables chromInfo and trackDb_$user in database '$tempDb'"
	exit 255
    endif
    echo "tempDb setting: '$tempDb' should not be an existing db"
    exit 255
endif


# Make up knownGenes table, adding uniProt ID. Load into database.
#	Takes 3 seconds.
txGeneFromBed ucscGenes.bed ucscGenes.picks ucscGenes.faa uniProt.fa refPep.fa ucscGenes.gp
hgLoadSqlTab $tempDb knownGene $kent/src/hg/lib/knownGene.sql ucscGenes.gp
hgLoadBed $tempDb knownAlt ucscSplice.bed

# Load in isoforms, canonical, and gene sequence tables
hgLoadSqlTab $tempDb knownIsoforms $kent/src/hg/lib/knownIsoforms.sql isoforms.tab
hgLoadSqlTab $tempDb knownCanonical $kent/src/hg/lib/knownCanonical.sql canonical.tab
hgPepPred $tempDb generic knownGenePep ucscGenes.faa
hgPepPred $tempDb generic knownGeneMrna ucscGenes.fa
hgPepPred $tempDb generic knownGeneTxPep ucscGenesTx.faa
hgPepPred $tempDb generic knownGeneTxMrna ucscGenesTx.fa

# Create a bunch of knownToXxx tables according to alignment overlap.  
# Takes about 3 minutes:
cd $dir
bedIntersect -minCoverage=1 ucscGenes.bed antibody.bed abGenes.bed
cat abGenes.bed |awk '{ print $4}' > abGenes.txt
hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db ensGene knownGene knownToEnsembl
hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db refGene knownGene knownToRefSeq
hgsql --skip-column-names -e "select mrnaAcc,locusLinkId from refLink" $db > refToLl.txt
hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db refGene knownGene knownToLocusLink -lookup=refToLl.txt

# Make up kgXref table.  Takes about 3 minutes.
time txGeneXref $db $tempDb $spDb ucscGenes.gp ucscGenes.info ucscGenes.picks ucscGenes.ev ucscGenes.xref
# 5.078u 4.871s 1:45.41 9.4%      0+0k 0+0io 0pf+0w

hgLoadSqlTab $tempDb kgXref $kent/src/hg/lib/kgXref.sql ucscGenes.xref

# Update knownToRefSeq to make it consistent with ucscGenes.xref.  Prior to
# this update, knownToRefSeq contains links to the RefSeq transcript that it
# most overlaps.  This is a preliminary mapping.  txGeneXref generates
# more reliable RefSeq associations, mostly from the CDS picks 
hgsql $tempDb -e "update knownToRefSeq kr, kgXref kx set kr.value = kx.refseq where kr.name = kx.kgID and length(kx.refseq) > 0"


# add NR_... RefSeq IDs into kgXref table.
hgsql $tempDb \
    -e 'update kgXref set refseq=mRNA where mRNA like "NR_%" and refseq=""'

# Make up and load kgColor table. Takes about a minute.
txGeneColor $spDb ucscGenes.info ucscGenes.picks ucscGenes.color
hgLoadSqlTab $tempDb kgColor $kent/src/hg/lib/kgColor.sql ucscGenes.color

# Load up kgTxInfo table. Takes 0.3 second
hgLoadSqlTab $tempDb kgTxInfo $kent/src/hg/lib/txInfo.sql ucscGenes.info

# Make up alias tables and load them. Takes a minute or so.
txGeneAlias $db $spDb ucscGenes.xref ucscGenes.ev oldToNew.tab foo.alias foo.protAlias
sort foo.alias | uniq > ucscGenes.alias
sort foo.protAlias | uniq > ucscGenes.protAlias
rm foo.alias foo.protAlias
hgLoadSqlTab $tempDb kgAlias $kent/src/hg/lib/kgAlias.sql ucscGenes.alias
hgLoadSqlTab $tempDb kgProtAlias $kent/src/hg/lib/kgProtAlias.sql ucscGenes.protAlias

# Load up kgProtMap2 table that says where exons are in terms of CDS
hgLoadPsl $tempDb ucscProtMap.psl -table=kgProtMap2

# Create a bunch of knownToXxx tables.  Takes about 3 minutes:
#if 0 # didn't do this, no Allen Brain, no gnfAtlas, no Tree Fam
# TODO
hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db allenBrainAli -type=psl knownGene knownToAllenBrain


hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db gnfAtlas2 knownGene knownToGnfAtlas2 '-type=bed 12'


# Create knownToTreefam table.  This is via a slow perl script that does remote queries of
# the treefam database..  Takes ~5 hours.  Can and should run it in the background really.
# Nothing else depends on the result.
cd $dir
hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db ensGene knownGene knownToEnsembl -noLoad
$kent/src/hg/protein/ensembl2treefam.pl < knownToEnsembl.tab > knownToTreefam.temp
grep -v -e ^# knownToTreefam.temp | cut -f 1,2 > knownToTreefam.tab
hgLoadSqlTab $tempDb knownToTreefam $kent/src/hg/lib/knownTo.sql knownToTreefam.tab



if ($db =~ hg*) then
    hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db HInvGeneMrna knownGene knownToHInv
    hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db affyU133Plus2 knownGene knownToU133Plus2
    hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db affyU133 knownGene knownToU133
    hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db affyU95 knownGene knownToU95
    knownToHprd $tempDb $genomes/$db/p2p/hprd/FLAT_FILES/HPRD_ID_MAPPINGS.txt
    hgsql $tempDb -e "delete k from knownToHprd k, kgXref x where k.name = x.kgID and x.geneSymbol = 'abParts'"
endif

if ($db =~ hg*) then
    time hgExpDistance $tempDb hgFixed.gnfHumanU95MedianRatio \
	    hgFixed.gnfHumanU95Exps gnfU95Distance  -lookup=knownToU95
    time hgExpDistance $tempDb hgFixed.gnfHumanAtlas2MedianRatio \
	hgFixed.gnfHumanAtlas2MedianExps gnfAtlas2Distance \
	-lookup=knownToGnfAtlas2
endif

if ($db =~ mm*) then
    hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db affyGnf1m knownGene knownToGnf1m
    hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db gnfAtlas2 knownGene knownToGnfAtlas2 '-type=bed 12'
    hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db affyU74  knownGene knownToU74
    hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db affyMOE430 knownGene knownToMOE430
    hgMapToGene -exclude=abGenes.txt -tempDb=$tempDb $db affyMOE430 -prefix=A: knownGene knownToMOE430A
    hgExpDistance $tempDb $db.affyGnfU74A affyGnfU74AExps affyGnfU74ADistance -lookup=knownToU74
    hgExpDistance $tempDb $db.affyGnfU74B affyGnfU74BExps affyGnfU74BDistance -lookup=knownToU74
    hgExpDistance $tempDb $db.affyGnfU74C affyGnfU74CExps affyGnfU74CDistance -lookup=knownToU74
    hgExpDistance $tempDb hgFixed.gnfMouseAtlas2MedianRatio \
	    hgFixed.gnfMouseAtlas2MedianExps gnfAtlas2Distance -lookup=knownToGnf1m
endif

#endif

# Update visiGene stuff
knownToVisiGene $tempDb -probesDb=$db
hgsql $tempDb -e "delete k from knownToVisiGene k, kgXref x where k.name = x.kgID and x.geneSymbol = 'abParts'"

vgGetText /usr/local/apache/cgi-bin/visiGeneData/visiGene.text $vgTextDbs
# probe has 26611 rows
# gene has 20413 rows
# imageProbe has 125765 rows

cd /usr/local/apache/cgi-bin/visiGeneData
ixIxx visiGene.text visiGene.ix visiGene.ixx
cd $dir

# Create Human P2P protein-interaction Gene Sorter columns
if ($db =~ hg*) then
hgLoadNetDist $genomes/$db/p2p/hprd/hprd.pathLengths $tempDb humanHprdP2P \
    -sqlRemap="select distinct value, name from knownToHprd"
hgLoadNetDist $genomes/$db/p2p/vidal/humanVidal.pathLengths $tempDb humanVidalP2P \
    -sqlRemap="select distinct locusLinkID, kgID from $db.refLink,kgXref where $db.refLink.mrnaAcc = kgXref.mRNA"
hgLoadNetDist $genomes/$db/p2p/wanker/humanWanker.pathLengths $tempDb humanWankerP2P \
    -sqlRemap="select distinct locusLinkID, kgID from $db.refLink,kgXref where $db.refLink.mrnaAcc = kgXref.mRNA"
endif


# Run nice Perl script to make all protein blast runs for
# Gene Sorter and Known Genes details page.  Takes about
# 45 minutes to run.
mkdir -p $dir/hgNearBlastp
cd $dir/hgNearBlastp
cat << _EOF_ > config.ra
# Latest human vs. other Gene Sorter orgs:
# mouse, rat, zebrafish, worm, yeast, fly

targetGenesetPrefix known
targetDb $tempDb
queryDbs $xdb $ratDb $fishDb $flyDb $wormDb $yeastDb

${tempDb}Fa $tempFa
${xdb}Fa $xdbFa
${ratDb}Fa $ratFa
${fishDb}Fa $fishFa
${flyDb}Fa $flyFa
${wormDb}Fa $wormFa
${yeastDb}Fa $yeastFa

buildDir $dir/hgNearBlastp
scratchDir $scratchDir/brHgNearBlastp
_EOF_


rm -rf  $scratchDir/brHgNearBlastp
doHgNearBlastp.pl -noLoad -clusterHub=swarm -distrHost=hgwdev -dbHost=hgwdev -workhorse=hgwdev config.ra |& tee do.log 
# *** All done!
# *** -noLoad was specified -- you can run this script manually to load mm10 tables:
#        run.mm10.mm10/loadPairwise.csh
#
# *** -noLoad was specified -- you can run these scripts manually to load mm10 tables:
#        run.mm10.hg19/loadPairwise.csh
#        run.mm10.rn5/loadPairwise.csh
#        run.mm10.danRer7/loadPairwise.csh
#        run.mm10.dm3/loadPairwise.csh
#        run.mm10.ce10/loadPairwise.csh
#        run.mm10.sacCer3/loadPairwise.csh
#
# *** -noLoad was specified -- you can run these scripts manually to load mmBlastTab in query databases:
#        run.hg19.mm10/loadPairwise.csh
#        run.rn5.mm10/loadPairwise.csh
#        run.danRer7.mm10/loadPairwise.csh
#        run.dm3.mm10/loadPairwise.csh
#        run.ce10.mm10/loadPairwise.csh
#        run.sacCer3.mm10/loadPairwise.csh


# Load self
cd $dir/hgNearBlastp/run.$tempDb.$tempDb
./loadPairwise.csh

# Load human and rat
cd $dir/hgNearBlastp/run.$tempDb.$xdb
hgLoadBlastTab $tempDb $xBlastTab -maxPer=1 out/*.tab
cd $dir/hgNearBlastp/run.$tempDb.$ratDb
hgLoadBlastTab $tempDb $rnBlastTab -maxPer=1 out/*.tab

# Remove non-syntenic hits for human and rat
# Takes a few minutes
mkdir -p /gbdb/$tempDb/liftOver
rm /gbdb/$tempDb/liftOver/${tempDb}To$RatDb.over.chain.gz /gbdb/$tempDb/liftOver/${tempDb}To$Xdb.over.chain.gz
ln -s $genomes/$db/bed/liftOver/${db}To$RatDb.over.chain.gz \
    /gbdb/$tempDb/liftOver/${tempDb}To$RatDb.over.chain.gz
ln -s $genomes/$db/bed/liftOver/${db}To${Xdb}.over.chain.gz \
    /gbdb/$tempDb/liftOver/${tempDb}To$Xdb.over.chain.gz

# delete non-syntenic genes from rat and human blastp tables
cd $dir/hgNearBlastp
synBlastp.csh $tempDb $xdb
# old number of unique query values: 43096
# old number of unique target values 22667
# new number of unique query values: 39713
# new number of unique target values 22032

hgsql -e "select  count(*) from hgBlastTab\G" $oldDb | tail -n +2
# count(*): 47124
hgsql -e "select  count(*) from hgBlastTab\G" $db | tail -n +2
# count(*): 39713

synBlastp.csh $tempDb $ratDb rgdGene2
# old number of unique query values: 38112
# old number of unique target values 10526
# new number of unique query values: 17901
# new number of unique target values 8085

hgsql -e "select  count(*) from rnBlastTab\G" $oldDb | tail -n +2
# count(*): 17832
hgsql -e "select  count(*) from rnBlastTab\G" $db | tail -n +2
# count(*): 17901


# Make reciprocal best subset for the blastp pairs that are too
# Far for synteny to help

# Us vs. fish
cd $dir/hgNearBlastp
set aToB = run.$tempDb.$fishDb
set bToA = run.$fishDb.$tempDb
cat $aToB/out/*.tab > $aToB/all.tab
cat $bToA/out/*.tab > $bToA/all.tab
blastRecipBest $aToB/all.tab $bToA/all.tab $aToB/recipBest.tab $bToA/recipBest.tab
hgLoadBlastTab $tempDb drBlastTab $aToB/recipBest.tab
hgLoadBlastTab $fishDb tfBlastTab $bToA/recipBest.tab
hgsql -e "select  count(*) from drBlastTab\G" $oldDb | tail -n +2
# count(*): 12904
hgsql -e "select  count(*) from drBlastTab\G" $db | tail -n +2
# count(*): 12881

# Us vs. fly
cd $dir/hgNearBlastp
set aToB = run.$tempDb.$flyDb
set bToA = run.$flyDb.$tempDb
cat $aToB/out/*.tab > $aToB/all.tab
cat $bToA/out/*.tab > $bToA/all.tab
blastRecipBest $aToB/all.tab $bToA/all.tab $aToB/recipBest.tab $bToA/recipBest.tab
hgLoadBlastTab $tempDb dmBlastTab $aToB/recipBest.tab
hgLoadBlastTab $flyDb tfBlastTab $bToA/recipBest.tab
hgsql -e "select  count(*) from dmBlastTab\G" $oldDb | tail -n +2
# count(*): 5923
hgsql -e "select  count(*) from dmBlastTab\G" $db | tail -n +2
# count(*): 5951

# Us vs. worm
cd $dir/hgNearBlastp
set aToB = run.$tempDb.$wormDb
set bToA = run.$wormDb.$tempDb
cat $aToB/out/*.tab > $aToB/all.tab
cat $bToA/out/*.tab > $bToA/all.tab
blastRecipBest $aToB/all.tab $bToA/all.tab $aToB/recipBest.tab $bToA/recipBest.tab
hgLoadBlastTab $tempDb ceBlastTab $aToB/recipBest.tab
hgLoadBlastTab $wormDb tfBlastTab $bToA/recipBest.tab

hgsql -e "select  count(*) from ceBlastTab\G" $oldDb | tail -n +2
# count(*): 4955
hgsql -e "select  count(*) from ceBlastTab\G" $db | tail -n +2
# count(*): 4957

# Us vs. yeast
cd $dir/hgNearBlastp
set aToB = run.$tempDb.$yeastDb
set bToA = run.$yeastDb.$tempDb
cat $aToB/out/*.tab > $aToB/all.tab
cat $bToA/out/*.tab > $bToA/all.tab
blastRecipBest $aToB/all.tab $bToA/all.tab $aToB/recipBest.tab $bToA/recipBest.tab
hgLoadBlastTab $tempDb scBlastTab $aToB/recipBest.tab
hgLoadBlastTab $yeastDb tfBlastTab $bToA/recipBest.tab

hgsql -e "select  count(*) from scBlastTab\G" $oldDb | tail -n +2
# count(*): 20619
# Don't know why scBlastTab is so big on mm9 on dev, it's 2,224 on RR.
hgsql -e "select  count(*) from scBlastTab\G" $db | tail -n +2
# count(*): 2398


# Clean up
cd $dir/hgNearBlastp
cat run.$tempDb.$tempDb/out/*.tab | gzip -c > run.$tempDb.$tempDb/all.tab.gz
gzip run.*/all.tab

# MAKE FOLDUTR TABLES 
# First set up directory structure and extract UTR sequence on hgwdev
cd $dir
mkdir -p rnaStruct
cd rnaStruct
mkdir -p utr3/split utr5/split utr3/fold utr5/fold
# these commands take some significant time
utrFa -nibPath=$genomes/$db/nib $tempDb knownGene utr3 utr3/utr.fa
utrFa -nibPath=$genomes/$db/nib $tempDb knownGene utr5 utr5/utr.fa

# Split up files and make files that define job.
faSplit sequence utr3/utr.fa 10000 utr3/split/s
faSplit sequence utr5/utr.fa 10000 utr5/split/s
ls -1 utr3/split > utr3/in.lst
ls -1 utr5/split > utr5/in.lst
cd utr3
cat << '_EOF_' > template
#LOOP
rnaFoldBig split/$(path1) fold
#ENDLOOP
'_EOF_'
gensub2 in.lst single template jobList
cp template ../utr5
cd ../utr5

gensub2 in.lst single template jobList

# Do cluster runs for UTRs
ssh $cpuFarm "cd $dir/rnaStruct/utr3; para make jobList"
ssh $cpuFarm "cd $dir/rnaStruct/utr3; para time"
#Completed: 9769 of 9769 jobs
#CPU time in finished jobs:     460454s    7674.23m   127.90h    5.33d  0.015 y
#IO & Wait Time:                 54259s     904.32m    15.07h    0.63d  0.002 y
#Average job time:                  53s       0.88m     0.01h    0.00d
#Longest finished job:            2204s      36.73m     0.61h    0.03d
#Submission to last job:          2778s      46.30m     0.77h    0.03d

ssh $cpuFarm "cd $dir/rnaStruct/utr5; para make jobList"
ssh $cpuFarm "cd $dir/rnaStruct/utr5; para time "
# Completed: 9289 of 9289 jobs
# CPU time in finished jobs:      11749s     195.82m     3.26h    0.14d  0.000 y
# IO & Wait Time:                 24522s     408.69m     6.81h    0.28d  0.001 y
# Average job time:                   4s       0.07m     0.00h    0.00d
# Longest finished job:              90s       1.50m     0.03h    0.00d
# Submission to last job:           170s       2.83m     0.05h    0.00d



# Load database
    cd $dir/rnaStruct/utr5
    hgLoadRnaFold $tempDb foldUtr5 fold
    cd ../utr3
    hgLoadRnaFold -warnEmpty $tempDb foldUtr3 fold

# Clean up
    rm -r split fold err batch.bak
    cd ../utr5
    rm -r split fold err batch.bak

# Make pfam run.  Actual cluster run is about 6 hours.
# TODO:  Should grab newest Pfam, but for the moment, use what we have
# mkdir -p /hive/data/outside/pfam/Pfam26.0
# cd /hive/data/outside/pfam/Pfam26.0
# wget ftp://ftp.sanger.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.gz
# gunzip Pfam-A.hmm.gz
#set pfamScratch = $scratchDir/pfamBR
#ssh $cpuFarm mkdir -p $pfamScratch
#ssh $cpuFarm cp /hive/data/outside/pfam/Pfam26.0/Pfam-A.hmm $pfamScratch

mkdir -p $dir/pfam
cd $dir/pfam
mkdir -p splitProt
faSplit sequence $dir/ucscGenes.faa 10000 splitProt/
mkdir -p result
ls -1 splitProt > prot.list
# /hive/data/outside/pfam/hmmpfam -E 0.1 /hive/data/outside/pfam/Pfam26.0/Pfam-A.hmm 
cat << '_EOF_' > doPfam
#!/bin/csh -ef
/hive/data/outside/pfam/hmmpfam -E 0.1 /hive/data/outside/pfam/current/Pfam_fs \
	splitProt/$1 > /scratch/tmp/$2.pf
mv /scratch/tmp/$2.pf $3
'_EOF_'
    # << happy emacs
chmod +x doPfam
cat << '_EOF_' > template
#LOOP
doPfam $(path1) $(root1) {check out line+ result/$(root1).pf}
#ENDLOOP
'_EOF_'
gensub2 prot.list single template jobList

ssh $cpuFarm "cd $dir/pfam; para make jobList"
ssh $cpuFarm "cd $dir/pfam; para time > run.time"
cat run.time

# CPU time in finished jobs:    2538170s   42302.84m   705.05h   29.38d  0.080 y
# IO & Wait Time:                415746s    6929.10m   115.48h    4.81d  0.013 y
# Average job time:                 305s       5.09m     0.08h    0.00d
# Longest finished job:            1737s      28.95m     0.48h    0.02d
# Submission to last job:         17004s     283.40m     4.72h    0.20d

# Make up pfamDesc.tab by converting pfam to a ra file first
cat << '_EOF_' > makePfamRa.awk
/^NAME/ {print}
/^ACC/ {print}
/^DESC/ {print; printf("\n");}
'_EOF_'
awk -f makePfamRa.awk  /hive/data/outside/pfam/current/Pfam_fs > pfamDesc.ra
raToTab -cols=ACC,NAME,DESC pfamDesc.ra stdout | \
   awk -F '\t' '{printf("%s\t%s\t%s\n", gensub(/\.[0-9]+/, "", "g", $1), $2, $3);}' > pfamDesc.tab

# Convert output to tab-separated file. 
cd $dir/pfam
catDir result | hmmPfamToTab -eValCol stdin ucscPfam.tab
cd $dir

# Convert output to knownToPfam table
awk '{printf("%s\t%s\n", $2, gensub(/\.[0-9]+/, "", "g", $1));}' \
	pfam/pfamDesc.tab > sub.tab
cut -f 1,4 pfam/ucscPfam.tab | subColumn 2 stdin sub.tab stdout | sort -u > knownToPfam.tab
rm -f sub.tab
hgLoadSqlTab $tempDb knownToPfam $kent/src/hg/lib/knownTo.sql knownToPfam.tab
hgLoadSqlTab $tempDb pfamDesc $kent/src/hg/lib/pfamDesc.sql pfam/pfamDesc.tab
hgsql $tempDb -e "delete k from knownToPfam k, kgXref x where k.name = x.kgID and x.geneSymbol = 'abParts'"

# Do scop run. Takes about 6 hours
# First get pfam global HMMs into /hive/data/outside/scop/scop.hmm 
# used existing ones...TODO
mkdir -p $dir/scop
cd $dir/scop
mkdir -p result
ls -1 ../pfam/splitProt > prot.list
cat << '_EOF_' > doScop
#!/bin/csh -ef
/hive/data/outside/pfam/hmmpfam -E 0.1 /hive/data/outside/scop/scop.hmm \
	../pfam/splitProt/$1 > /scratch/tmp/$2.pf
mv /scratch/tmp/$2.pf $3
'_EOF_'
    # << happy emacs
chmod +x doScop
cat << '_EOF_' > template
#LOOP
doScop $(path1) $(root1) {check out line+ result/$(root1).pf}
#ENDLOOP
'_EOF_'
    # << happy emacs
gensub2 prot.list single template jobList

ssh $cpuFarm "cd $dir/scop; para make jobList"
ssh $cpuFarm "cd $dir/scop; para time > run.time"
cat run.time

# Completed: 9671 of 9671 jobs
# CPU time in finished jobs:    2718190s   45303.16m   755.05h   31.46d  0.086 y
# IO & Wait Time:                594796s    9913.27m   165.22h    6.88d  0.019 y
# Average job time:                 343s       5.71m     0.10h    0.00d
# Longest finished job:            2411s      40.18m     0.67h    0.03d
# Submission to last job:         13659s     227.65m     3.79h    0.16d

# Convert scop output to tab-separated files
cd $dir
catDir scop/result | \
	hmmPfamToTab -eValCol -scoreCol stdin scopPlusScore.tab
scopCollapse scopPlusScore.tab /hive/data/outside/scop/model.tab ucscScop.tab \
	scopDesc.tab knownToSuper.tab
hgLoadSqlTab $tempDb knownToSuper $kent/src/hg/lib/knownToSuper.sql knownToSuper.tab
hgsql $tempDb -e "delete k from knownToSuper k, kgXref x where k.gene = x.kgID and x.geneSymbol = 'abParts'"

hgLoadSqlTab $tempDb scopDesc $kent/src/hg/lib/scopDesc.sql scopDesc.tab
hgLoadSqlTab $tempDb ucscScop $kent/src/hg/lib/ucscScop.sql ucscScop.tab

#if 0 TODO
# Regenerate ccdsKgMap table
$kent/src/hg/makeDb/genbank/bin/x86_64/mkCcdsGeneMap  -db=$tempDb -loadDb $db.ccdsGene knownGene ccdsKgMap
#endif

cd $dir
# Map old to new mapping
set oldGeneBed=$oldDb.$db.kg.bed
txGeneExplainUpdate2 $oldGeneBed ucscGenes.bed kgOldToNew.tab
hgLoadSqlTab $tempDb kg${lastVer}ToKg${curVer} $kent/src/hg/lib/kg1ToKg2.sql kgOldToNew.tab

# Build kgSpAlias table, which combines content of both kgAlias and kgProtAlias tables.

hgsql $tempDb -N -e \
    'select kgXref.kgID, spID, alias from kgXref, kgAlias where kgXref.kgID=kgAlias.kgID' > kgSpAlias_0.tmp
         
hgsql $tempDb -N -e \
    'select kgXref.kgID, spID, alias from kgXref, kgProtAlias where kgXref.kgID=kgProtAlias.kgID'\
    >> kgSpAlias_0.tmp
cat kgSpAlias_0.tmp|sort -u  > kgSpAlias.tab
rm kgSpAlias_0.tmp

hgLoadSqlTab $tempDb kgSpAlias $kent/src/hg/lib/kgSpAlias.sql kgSpAlias.tab


# Do BioCyc Pathways build
    mkdir -p $dir/bioCyc
    cd $dir/bioCyc
    grep -v '^#' $bioCycPathways > pathways.tab
    grep -v '^#' $bioCycGenes > genes.tab
    kgBioCyc1 genes.tab pathways.tab $tempDb bioCycPathway.tab bioCycMapDesc.tab
    hgLoadSqlTab $tempDb bioCycPathway $kent/src/hg/lib/bioCycPathway.sql ./bioCycPathway.tab
    hgLoadSqlTab $tempDb bioCycMapDesc $kent/src/hg/lib/bioCycMapDesc.sql ./bioCycMapDesc.tab

# Do KEGG Pathways build (borrowing Fan Hus's strategy from hg19.txt)
    mkdir -p $dir/kegg
    cd $dir/kegg

    # Make the keggMapDesc table, which maps KEGG pathway IDs to descriptive names
    cp /cluster/data/hg19/bed/ucsc.13/kegg/map_title.tab .
    # wget --timestamping ftp://ftp.genome.jp/pub/kegg/pathway/map_title.tab
    cat map_title.tab | sed -e 's/\t/\thsa\t/' > j.tmp
    cut -f 2 j.tmp >j.hsa
    cut -f 1,3 j.tmp >j.1
    paste j.hsa j.1 |sed -e 's/\t//' > keggMapDesc.tab
    rm j.hsa j.1 j.tmp
    hgLoadSqlTab $tempDb keggMapDesc $kent/src/hg/lib/keggMapDesc.sql keggMapDesc.tab

    # Following in two-step process, build/load a table that maps UCSC Gene IDs
    # to LocusLink IDs and to KEGG pathways.  First, make a table that maps 
    # LocusLink IDs to KEGG pathways from the downloaded data.  Store it temporarily
    # in the keggPathway table, overloading the schema.
    cp /cluster/data/mm9/bed/ucsc.12/kegg/mmu_pathway.list .

    cat mmu_pathway.list| sed -e 's/path://'|sed -e 's/:/\t/' > j.tmp
    hgLoadSqlTab $tempDb keggPathway $kent/src/hg/lib/keggPathway.sql j.tmp

    # Next, use the temporary contents of the keggPathway table to join with
    # knownToLocusLink, creating the real content of the keggPathway table.
    # Load this data, erasing the old temporary content
    hgsql $tempDb -B -N -e \
    'select distinct name, locusID, mapID from keggPathway p, knownToLocusLink l where p.locusID=l.value' \
    >keggPathway.tab
    hgLoadSqlTab $tempDb \
	keggPathway $kent/src/hg/lib/keggPathway.sql  keggPathway.tab

   # Finally, update the knownToKeggEntrez table from the keggPathway table.
   hgsql $tempDb -B -N -e 'select kgId, mapID, mapID, "+", locusID from keggPathway' \
        |sort -u| sed -e 's/\t+\t/+/' > knownToKeggEntrez.tab
   hgLoadSqlTab $tempDb knownToKeggEntrez $kent/src/hg/lib/knownToKeggEntrez.sql \
        knownToKeggEntrez.tab
    hgsql $tempDb -e "delete k from knownToKeggEntrez k, kgXref x where k.name = x.kgID and x.geneSymbol = 'abParts'"

# Make spMrna table (useful still?)
   cd $dir
   hgsql $db -N -e "select spDisplayID,kgID from kgXref where spDisplayID != ''" > spMrna.tab;
   hgLoadSqlTab $tempDb spMrna $kent/src/hg/lib/spMrna.sql spMrna.tab


# Do CGAP tables 

    mkdir -p $dir/cgap
    cd $dir/cgap
    
    wget --timestamping -O Mm_GeneData.dat "ftp://ftp1.nci.nih.gov/pub/CGAP/Mm_GeneData.dat"
    hgCGAP Mm_GeneData.dat
        
    cat cgapSEQUENCE.tab cgapSYMBOL.tab cgapALIAS.tab|sort -u > cgapAlias.tab
    hgLoadSqlTab $tempDb cgapAlias $kent/src/hg/lib/cgapAlias.sql ./cgapAlias.tab

    hgLoadSqlTab $tempDb cgapBiocPathway $kent/src/hg/lib/cgapBiocPathway.sql ./cgapBIOCARTA.tab

    cat cgapBIOCARTAdesc.tab|sort -u > cgapBIOCARTAdescSorted.tab
    hgLoadSqlTab $tempDb cgapBiocDesc $kent/src/hg/lib/cgapBiocDesc.sql cgapBIOCARTAdescSorted.tab



cd $dir
# Make PCR target for UCSC Genes, Part 1.
# 1. Get a set of IDs that consist of the UCSC Gene accession concatenated with the
#    gene symbol, e.g. uc010nxr.1__DDX11L1
hgsql $tempDb -N -e 'select kgId,geneSymbol from kgXref' \
    | perl -wpe 's/^(\S+)\t(\S+)/$1\t${1}__$2/ || die;' \
      > idSub.txt

# 2. Get a file of per-transcript fasta sequences that contain the sequences of each 
#    UCSC Genes transcript, with this new ID in the place of the UCSC Genes accession.
#    Convert that file to TwoBit format and soft-link it into /gbdb/hg19/targetDb/
subColumn 4 ucscGenes.bed idSub.txt ucscGenesIdSubbed.bed
sequenceForBed -keepName -db=$db -bedIn=ucscGenesIdSubbed.bed -fastaOut=stdout \
    | faToTwoBit stdin kgTargetSeq${curVer}.2bit 
mkdir -p /gbdb/$db/targetDb/
rm -f /gbdb/$db/targetDb/kgTargetSeq${curVer}.2bit 
ln -s $dir/kgTargetSeq${curVer}.2bit /gbdb/$db/targetDb/
# Load the table kgTargetAli, which shows where in the genome these targets are.
cut -f 1-10 ucscGenes.gp | genePredToFakePsl $tempDb stdin kgTargetAli.psl /dev/null
hgLoadPsl $tempDb kgTargetAli.psl

#if 0 # didn't do this first time through
# NOW SWAP IN TABLES FROM TEMP DATABASE TO MAIN DATABASE.
# You'll need superuser powers for this step.....

# Save old known genes and kgXref tables
sudo ~kent/bin/copyMysqlTable $db knownGene $tempDb knownGeneOld$lastVer
sudo ~kent/bin/copyMysqlTable $db kgXref $tempDb kgXrefOld$lastVer

# Create backup database
hgsqladmin create ${db}Backup

# Drop tempDb history table and chromInfo, we don't want to swap them in!
hgsql -e "drop table history" $tempDb
hgsql -e "drop table chromInfo" $tempDb
hgsql -e "drop table tableList" $tempDb

# Swap in new tables, moving old tables to backup database.
sudo ~kent/bin/swapInMysqlTempDb $tempDb $db ${db}Backup

# Update database links.
sudo rm /var/lib/mysql/uniProt
sudo ln -s /var/lib/mysql/$spDb /var/lib/mysql/uniProt
sudo rm /var/lib/mysql/proteome
sudo ln -s /var/lib/mysql/$pbDb /var/lib/mysql/proteome
hgsqladmin flush-tables

#endif

# Make full text index.  Takes a minute or so.  After this the genome browser
# tracks display will work including the position search.  The genes details
# page, gene sorter, and proteome browser still need more tables.
mkdir -p $dir/index
cd $dir/index
hgKgGetText $db knownGene.text 
ixIxx knownGene.text knownGene.ix knownGene.ixx
rm -f /gbdb/$db/knownGene.ix /gbdb/$db/knownGene.ixx
ln -s $dir/index/knownGene.ix  /gbdb/$db/knownGene.ix
ln -s $dir/index/knownGene.ixx /gbdb/$db/knownGene.ixx


# 3. Ask cluster-admin to start an untranslated, -stepSize=5 gfServer on       
# /gbdb/$db/targetDb/kgTargetSeq${curVer}.2bit

# 4. On hgwdev, insert new records into blatServers and targetDb, using the 
# host (field 2) and port (field 3) specified by cluster-admin.  Identify the
# blatServer by the keyword "$db"Kg with the version number appended
hgsql hgcentraltest -e \
      'INSERT into blatServers values ("mm10Kgv13", "blat4a", 17829, 0, 1);'
hgsql hgcentraltest -e \                                                    
      'INSERT into targetDb values("mm10Kgv13", "UCSC Genes", \
         "mm10", "kgTargetAli", "", "", \
         "/gbdb/mm10/targetDb/kgTargetSeq.2bit", 1, now(), "");'


cd $dir


#
# Finally, need to wait until after testing, but update databases in other organisms
# with blastTabs

# Load blastTabs
cd $dir/hgNearBlastp
hgLoadBlastTab $xdb $blastTab run.$xdb.$tempDb/out/*.tab
hgLoadBlastTab $ratDb $blastTab run.$ratDb.$tempDb/out/*.tab 
hgLoadBlastTab $flyDb $blastTab run.$flyDb.$tempDb/recipBest.tab
hgLoadBlastTab $wormDb $blastTab run.$wormDb.$tempDb/recipBest.tab
hgLoadBlastTab $yeastDb $blastTab run.$yeastDb.$tempDb/recipBest.tab

# Do synteny on mouse/human/rat
synBlastp.csh $xdb $db
# old number of unique query values: 60302
# old number of unique target values 22241
# new number of unique query values: 57026
# new number of unique target values 21771

synBlastp.csh $ratDb $db rgdGene2 knownGene
#old number of unique query values: 11267
# old number of unique target values 11104
#new number of unique query values: 8399
#new number of unique target values 8530

# Clean up
rm -r run.*/out

# Last step in setting up isPCR: after the new UCSC Genes with the new Known Gene isPcr
# is released, take down the old isPcr gfServer  
#
