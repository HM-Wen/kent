/* stsAlias.h was originally generated by the autoSql program, which also 
 * generated stsAlias.c and stsAlias.sql.  This header links the database and
 * the RAM representation of objects. */

#ifndef STSALIAS_H
#define STSALIAS_H

struct stsAlias
/* STS marker aliases and associated identification numbers */
    {
    struct stsAlias *next;  /* Next in singly linked list. */
    char *alias;	/* STS marker name */
    unsigned identNo;	/* Identification number of STS marker */
    char *trueName;	/* Official UCSC name for marker */
    };

void stsAliasStaticLoad(char **row, struct stsAlias *ret);
/* Load a row from stsAlias table into ret.  The contents of ret will
 * be replaced at the next call to this function. */

struct stsAlias *stsAliasLoad(char **row);
/* Load a stsAlias from row fetched with select * from stsAlias
 * from database.  Dispose of this with stsAliasFree(). */

struct stsAlias *stsAliasLoadAll(char *fileName);
/* Load all stsAlias from a tab-separated file.
 * Dispose of this with stsAliasFreeList(). */

struct stsAlias *stsAliasCommaIn(char **pS, struct stsAlias *ret);
/* Create a stsAlias out of a comma separated string. 
 * This will fill in ret if non-null, otherwise will
 * return a new stsAlias */

void stsAliasFree(struct stsAlias **pEl);
/* Free a single dynamically allocated stsAlias such as created
 * with stsAliasLoad(). */

void stsAliasFreeList(struct stsAlias **pList);
/* Free a list of dynamically allocated stsAlias's */

void stsAliasOutput(struct stsAlias *el, FILE *f, char sep, char lastSep);
/* Print out stsAlias.  Separate fields with sep. Follow last field with lastSep. */

#define stsAliasTabOut(el,f) stsAliasOutput(el,f,'\t','\n');
/* Print out stsAlias as a line in a tab-separated file. */

#define stsAliasCommaOut(el,f) stsAliasOutput(el,f,',',',');
/* Print out stsAlias as a comma separated list including final comma. */

#endif /* STSALIAS_H */

