# cddDesc.sql was originally generated by the autoSql program, which also 
# generated cddDesc.c and cddDesc.h.  This creates the database representation of
# an object which can be loaded and saved from RAM in a fairly 
# automatic way.

#Conserved Domain Description
CREATE TABLE cddDesc (
    cddid int unsigned not null,	# identifier
    accession varchar(255) not null,	# accession
    cddname varchar(255) not null,	# Name of domain
    name varchar(255) not null,	# hit name
    cdddesc varchar(255) not null,	# descriptive name
    cddlength int unsigned not null,	# length
              #Indices
    PRIMARY KEY(cddid)
);