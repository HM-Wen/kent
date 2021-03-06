# bedDetail.sql was originally generated by the autoSql program, which also 
# generated bedDetail.c and bedDetail.h.  This creates the database representation of
# an object which can be loaded and saved from RAM in a fairly 
# automatic way.

#Browser extensible data, with extended fields for detail page
CREATE TABLE bedDetail (
    chrom varchar(255) not null,	# Reference sequence chromosome or scaffold
    chromStart int unsigned not null,	# Start position in chromosome
    chromEnd int unsigned not null,	# End position in chromosome
    name varchar(255) not null,	# Short Name of item
    score int unsigned,	# Score from 0-1000
    strand char(1),	# + or -
    thickStart int unsigned,	# Start of where display should be thick (start codon)
    thickEnd int unsigned,	# End of where display should be thick (stop codon)
    reserved int unsigned,	# Used as itemRgb as of 2004-11-22
    blockCount int,	# Number of blocks
    blockSizes longblob,	# Comma separated list of block sizes
    chromStarts longblob,	# Start positions relative to chromStart
    id varchar(255) not null,	# ID to bed used in URL to link back
    description longblob not null,	# Long description of item for the details page
              #Indices
    INDEX(chrom, chromStart)
);
