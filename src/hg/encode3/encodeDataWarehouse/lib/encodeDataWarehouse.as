table edwSettings
"Settings used to configure warehouse"
    (
    uint id primary auto;  "Settings ID"
    string name unique;	"Settings name, can't be reused"
    string val index; "Settings value, some undefined but not huge thing"
    )

table edwUser
"Someone who submits files to or otherwise interacts with big data warehouse"
    (
    uint id primary auto;      "Autoincremented user ID"
    string email unique;   "Email address - required"
    char[37] uuid index; "Help to synchronize us with Stanford."
    byte isAdmin;	"If true the use can modify other people's files too."
    )

table edwScriptRegistry
"A script that is authorized to submit on behalf of a user"
    (
    uint id primary auto;	"Autoincremented script ID"
    uint userId index;		"Associated user"
    string name unique;		"Script name - unique in system and autogenerated"
    lstring description;	"Script description"
    string secretHash;		"Hashed script password"
    int submitCount;		"Number of submissions attempted"
    )

table edwHost
"A web host we have collected files from - something like www.ncbi.nlm.gov or google.com"
    (
    uint id primary auto;            "Autoincremented host id"
    string name unique;        "Name (before DNS lookup)"
    bigInt lastOkTime;   "Last time host was ok in seconds since 1970"
    bigInt lastNotOkTime;  "Last time host was not ok in seconds since 1970"
    bigInt firstAdded;     "Time host was first seen"
    lstring errorMessage; "If non-empty contains last error message from host. If empty host is ok"
    bigInt openSuccesses;  "Number of times files have been opened ok from this host"
    bigInt openFails;      "Number of times files have failed to open from this host"
    bigInt historyBits; "Open history with most recent in least significant bit. 0 for connection failed, 1 for success"
    int paraFetchStreams; 	"Number of open streams for paraFetch command.  10 for most places, 30 for Barcelona"
    )

table edwSubmitDir
"An external data directory we have collected a submit from"
    (
    uint id primary auto;            "Autoincremented id"
    lstring url index[64];        "Web-mounted directory. Includes protocol, host, and final '/'"
    uint hostId index;        "Id of host it's on"
    bigInt lastOkTime;   "Last time submit dir was ok in seconds since 1970"
    bigInt lastNotOkTime;  "Last time submit dir was not ok in seconds since 1970"
    bigInt firstAdded;     "Time submit dir was first seen"
    lstring errorMessage; "If non-empty contains last error message from dir. If empty dir is ok"
    bigInt openSuccesses;  "Number of times files have been opened ok from this dir"
    bigInt openFails;      "Number of times files have failed to open from this dir"
    bigInt historyBits; "Open history with most recent in least significant bit. 0 for upload failed, 1 for success"
    )

table edwFile
"A file we are tracking that we intend to and maybe have uploaded"
    (
    uint id primary auto;                    "Autoincrementing file id"
    uint submitId index;              "Links to id in submit table"
    uint submitDirId index;           "Links to id in submitDir table"
    lstring submitFileName index[64];     "File name in submit relative to submit dir"
    lstring edwFileName index[32];        "File name in big data warehouse relative to edw root dir"
    bigInt startUploadTime;     "Time when upload started - 0 if not started"
    bigInt endUploadTime;       "Time when upload finished - 0 if not finished"
    bigInt updateTime;          "Update time (on system it was uploaded from)"
    bigInt size;                "File size in manifest"
    char[32] md5 index;               "md5 sum of file contents"
    lstring tags;               "CGI encoded name=val pairs from manifest"
    lstring errorMessage; "If non-empty contains last error message from upload. If empty upload is ok"
    string deprecated; "If non-empty why you shouldn't use this file any more."
    uint replacedBy;   "If non-zero id of file that replaces this one."
    )

table edwSubmit
"A data submit, typically containing many files.  Always associated with a submit dir."
    (
    uint id primary auto;                 "Autoincremented submit id"
    lstring url index[32];              "Url to validated.txt format file. We copy this file over and give it a fileId if we can." 
    bigInt startUploadTime;   "Time at start of submit"
    bigInt endUploadTime;     "Time at end of upload - 0 if not finished"
    uint userId index;        "Connects to user table id field"
    uint submitFileId index;       "Points to validated.txt file for submit."
    uint submitDirId index;    "Points to the submitDir"
    uint fileCount;          "Number of files that will be in submit if it were complete."
    uint oldFiles;           "Number of files in submission that were already in warehouse."
    uint newFiles;           "Number of files in submission that are newly uploaded."
    bigInt byteCount;        "Total bytes in submission including old and new"
    bigInt oldBytes;         "Bytes in old files."
    bigInt newBytes;         "Bytes in new files (so far)."
    lstring errorMessage; "If non-empty contains last error message. If empty submit is ok"
    uint fileIdInTransit; "edwFile.id of file currently being transferred or zero"
    uint metaChangeCount; "Number of files where metadata changed by submission"
    )

table edwSubscriber
"Subscribers can have programs that are called at various points during data submission"
    (
    uint id primary auto;             "ID of subscriber"
    string name;         "Name of subscriber"
    double runOrder;     "Determines order subscribers run in. In case of tie lowest id wins."
    string filePattern;  "A string with * and ? wildcards to match files we care about"
    string dirPattern;   "A string with * and ? wildcards to match hub dir URLs we care about"
    lstring tagPattern;  "A cgi-encoded string of tag=wildcard pairs."
    string onFileEndUpload;     "A unix command string to run with a %u where file id goes"
    )

table edwAssembly
"An assembly - includes reference to a two bit file, and a little name and summary info."
    (
    uint id primary auto;    "Assembly ID"
    uint taxon; "NCBI taxon number"
    string name;  "Some human readable name to distinguish this from other collections of DNA"
    string ucscDb;  "Which UCSC database (mm9?  hg19?) associated with it."
    uint twoBitId;  "File ID of associated twoBit file"
    bigInt baseCount;  "Count of bases including N's"
    bigInt realBaseCount;   "Count of non-N bases in assembly"
    uint seqCount; "Number of chromosomes or other distinct sequences in assembly"
    )

table edwBiosample
"A biosample - not much info here, just enough to drive analysis pipeline"
    (
    uint id primary auto;  "Biosample id"
    string term index;	   "Human readable.  Shared with ENCODE2."
    uint taxon;	    "NCBI taxon number - 9606 for human."
    string sex;	"One letter code: M male, F female, B both, U unknown"
    )

table edwExperiment
"An experiment - ideally will include a couple of biological replicates. Downloaded from Stanford."
    (
    char[16] accession unique; "Something like ENCSR000CFA. ID shared with Stanford."
    string dataType; "Something liek RNA-seq, DNase-seq, ChIP-seq. Computed at UCSC."
    string lab; "Lab PI name and institution. Is lab.title at Stanford."
    string biosample;  "Cell line name, tissue source, etc. Is biosample_term_name at Stanford."
    string rfa;  "Something like 'ENCODE2' or 'ENCODE3'.  Is award.rfa at Stanford."
    string assayType; "Similar to dataType. Is assay_term_name at Stanford."
    string ipTarget; "The target for the immunoprecipitation in ChIP & RIP." 
    string control; "Primary control for experiment.  Usually another experiment accession."
    )

table edwValidFile
"A file that has been uploaded, the format checked, and for which at least minimal metadata exists"
    (
    uint id primary auto;          "ID of validated file"
    char[16] licensePlate index;  "A abc123 looking license-platish thing."
    uint fileId unique;      "Pointer to file in main file table"
    string format index[12];    "What format it's in from manifest"
    string outputType index[16]; "What output_type it is from manifest"
    string experiment index[16]; "What experiment it's in from manifest"
    string replicate;  "What replicate it is from manifest.  Values 1,2,3... pooled, or ''"
    string validKey;  "The valid_key tag from manifest"
    string enrichedIn; "The enriched_in tag from manifest"
    string ucscDb;    "Something like hg19 or mm9"

    bigint itemCount; "# of items in file: reads for fastqs, lines for beds, bases w/data for wig."
    bigint basesInItems; "# of bases in items"
    bigint sampleCount; "# of items in sample if we are just subsampling as we do for reads." 
    bigint basesInSample; "# of bases in our sample"
    string sampleBed;   "Path to a temporary bed file holding sample items"
    double mapRatio;    "Proportion of items that map to genome"
    double sampleCoverage; "Proportion of assembly covered by at least one item in sample"
    double depth;   "Estimated genome-equivalents covered by possibly overlapping data"
    byte singleQaStatus;  "0 = untested, 1 =  pass, -1 = fail, 2 = forced pass, -2 = forced fail"
    byte replicateQaStatus;  "0 = untested, 1 = pass, -1 = fail, 2 = forced pass, -2 = forced fail"
    string technicalReplicate; "Manifest's technical_replicate tag. Values 1,2,3... pooled or ''"
    string pairedEnd; "The paired_end tag from the manifest.  Values 1,2 or ''"
    byte qaVersion; "Version of QA pipeline making status decisions"
    double uniqueMapRatio; "Fraction of reads that map uniquely to genome for bams and fastqs"
    )

table edwQaFail
"Record of a QA failure."
    (
    uint id primary auto;   "ID of failure"
    uint fileId index;	"File that failed"
    uint qaVersion; "QA pipeline version"
    lstring reason; "reason for failure"
    )

table edwFastqFile
"info on a file in fastq short read format beyond what's in edwValidFile"
    (
    uint id primary auto;  "ID in this table"
    uint fileId unique;	"ID in edwFile table"
    bigint sampleCount; "# of reads in sample." 
    bigint basesInSample; "# of bases in sample."
    string sampleFileName; "Name of file containing sampleCount randomly selected items from file."
    bigint readCount; "# of reads in file"
    bigint baseCount; "# of bases in all reads added up"
    double readSizeMean; "Average read size"
    double readSizeStd;  "Standard deviation of read size"
    int readSizeMin;  "Minimum read size"
    int readSizeMax; "Maximum read size"
    double qualMean;  "Mean quality scored as 10*-log10(errorProbability) or close to it.  >25 is good"
    double qualStd;   "Standard deviation of quality"
    double qualMin;   "Minimum observed quality"
    double qualMax;   "Maximum observed quality"
    string qualType;  "For fastq files either 'sanger' or 'illumina'
    int qualZero;  "For fastq files offset to get to zero value in ascii encoding"
    double atRatio;  "Ratio of A+T to total sequence (not including Ns)"
    double aRatio; "Ratio of A to total sequence (including Ns)"
    double cRatio; "Ratio of C to total sequence (including Ns)"
    double gRatio; "Ratio of G to total sequence (including Ns)"
    double tRatio; "Ratio of T to total sequence (including Ns)"
    double nRatio; "Ratio of N or . to total sequence"
    double[readSizeMax] qualPos;  "Mean value for each position in a read up to some max."
    double[readSizeMax] aAtPos;   "% of As at each pos"
    double[readSizeMax] cAtPos;   "% of Cs at each pos"
    double[readSizeMax] gAtPos;   "% of Gs at each pos"
    double[readSizeMax] tAtPos;   "% of Ts at each pos"
    double[readSizeMax] nAtPos;   "% of '.' or 'N' at each pos"
    )

table edwBamFile
"Info on what is in a bam file beyond whet's in edwValidFile"
    (
    uint id primary auto;	"ID in this table"
    uint fileId unique; "ID in edwFile table."
    byte isPaired;	"Set to 1 if paired reads, 0 if single"
    byte isSortedByTarget; "Set to 1 if sorted by target,pos"
    bigint readCount; "# of reads in file"
    bigint readBaseCount; "# of bases in all reads added up"
    bigint mappedCount; "# of reads that map"
    bigint uniqueMappedCount; "# of reads that map to a unique position"
    double readSizeMean; "Average read size"
    double readSizeStd;  "Standard deviation of read size"
    int readSizeMin;  "Minimum read size"
    int readSizeMax; "Maximum read size"
    int u4mReadCount; "Uniquely-mapped 4 million read actual read # (usually 4M)"
    int u4mUniquePos;  "Unique positions in target of the 4M reads that map to single pos"
    double u4mUniqueRatio; "u4mUniqPos/u4mReadCount - measures library diversity"
    bigInt targetBaseCount;  "Count of bases in mapping target"
    uint targetSeqCount; "Number of chromosomes or other distinct sequences in mapping target"
    )

table edwQaEnrichTarget
"A target for our enrichment analysis."
    (
    uint id primary auto;    "ID of this enrichment target"
    uint assemblyId index; "Which assembly this goes to"
    string name index;  "Something like 'exon' or 'promoter'"
    uint fileId;    "A simple BED 3 format file that defines target. Bases covered are unique"
    bigint targetSize;  "Total number of bases covered by target"
    )

table edwQaEnrich
"An enrichment analysis applied to file."
    (
    uint id primary auto;    "ID of this enrichment analysis"
    uint fileId index;  "File we are looking at skeptically"
    uint qaEnrichTargetId;  "Information about a target for this analysis"
    bigInt targetBaseHits;  "Number of hits to bases in target"
    bigInt targetUniqHits;  "Number of unique bases hit in target"
    double coverage;    "Coverage of target - just targetUniqHits/targetSize"
    double enrichment;  "Amount we hit target/amount we hit genome"
    double uniqEnrich;  "coverage/sampleCoverage"
    )

table edwQaContamTarget
"A target for our contamination analysis."
    (
    uint id primary auto;   "ID of this contamination target"
    uint assemblyId unique;  "Assembly we're aligning against to check  for contamination."
    )

table edwQaContam
"Results of contamination analysis of one file against one target"
    (
    uint id primary auto;   "ID of this contamination analysis"
    uint fileId index;  "File we are looking at skeptically"
    uint qaContamTargetId;  "Information about a target for this analysis"
    double mapRatio;    "Proportion of items that map to target"
    )

table edwQaRepeat
"What percentage of data set aligns to various repeat classes."
    (
    uint id primary auto;   "ID of this repeat analysis."
    uint fileId index;   "File we are analysing."
    string repeatClass;	"RepeatMasker high end classification,  or 'total' for all repeats."
    double mapRatio;	"Proportion that map to this repeat."
    )

table edwQaPairSampleOverlap
"A comparison of the amount of overlap between two samples that cover ~0.1% to 10% of target."
    (
    uint id primary auto;    "Id of this qa pair"
    uint elderFileId index;   "Id of elder (smaller fileId) in correlated pair"
    uint youngerFileId index;  "Id of younger (larger fileId) in correlated pair"
    bigInt elderSampleBases;   "Number of bases in elder sample"
    bigInt youngerSampleBases; "Number of bases in younger sample"
    bigInt sampleOverlapBases; "Number of bases that overlap between younger and elder sample"
    double sampleSampleEnrichment; "Amount samples overlap more than expected."
    )

table edwQaPairCorrelation
"A correlation between two files of the same type."
    (
    uint id primary auto;    "Id of this correlation pair"
    uint elderFileId index;   "Id of elder (smaller fileId) in correlated pair"
    uint youngerFileId index;  "Id of younger (larger fileId) in correlated pair"
    double pearsonInEnriched;  "Pearson's R inside enriched areas where there is overlap"
    double pearsonOverall; "Pearson's R over all places where both have data"
    double pearsonClipped; "Pearson's R clipped at two standard deviations up from the mean" 
    )

table edwQaPairedEndFastq
"Information about two paired-end fastqs"
    (
    uint id primary auto; "Id of this set of paired end files"
    uint fileId1 index; "Id of first in pair"
    uint fileId2 index; "Id of second in pair"
    double concordance;  "% of uniquely aligning reads where pairs nearby and point right way"
    double distanceMean; "Average distance between reads"
    double distanceStd;  "Standard deviation of distance"
    double distanceMin;	 "Minimum distance"
    double distanceMax;  "Maximum distatnce"
    byte recordComplete; "Flag to avoid a race condition. Ignore record if this is 0"
    )


table edwJob
"A job to be run asynchronously and not too many all at once."
    (
    uint id primary auto;    "Job id"
    lstring commandLine; "Command line of job"
    bigInt startTime; "Start time in seconds since 1970"
    bigInt endTime; "End time in seconds since 1970"
    lstring stderr; "The output to stderr of the run - may be nonempty even with success"
    int returnCode; "The return code from system command - 0 for success"
    int pid;	"Process ID for running processes"
    )

table edwSubmitJob
"A submission job to be run asynchronously and not too many all at once."
    (
    uint id primary auto;    "Job id"
    lstring commandLine; "Command line of job"
    bigInt startTime; "Start time in seconds since 1970"
    bigInt endTime; "End time in seconds since 1970"
    lstring stderr; "The output to stderr of the run - may be nonempty even with success"
    int returnCode; "The return code from system command - 0 for success"
    int pid;	"Process ID for running processes"
    )
