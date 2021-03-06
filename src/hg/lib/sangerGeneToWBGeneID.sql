# sangerGeneToWBGeneID.sql was originally generated by the autoSql program, which also 
# generated sangerGeneToWBGeneID.c and sangerGeneToWBGeneID.h.  This creates the database representation of
# an object which can be loaded and saved from RAM in a fairly 
# automatic way.

#sanger gene names to WormBase Gene IDs translation
CREATE TABLE sangerGeneToWBGeneID (
    sangerGene varchar(255) not null,	# sangerGene name
    WBGeneID varchar(255) not null,	# WormBase Gene ID
              #Indices
    PRIMARY KEY(sangerGene)
);
