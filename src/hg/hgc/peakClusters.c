/* Stuff to display details on tracks that are clusters of peaks (items) in other tracks. 
 * In particular peaks in either ENCODE narrowPeak or broadPeak settings, and residing in
 * composite tracks. 
 *
 * These come in two main forms currently:
 *     DNAse hypersensitive clusters - peaks clustered across cell lines stored in bed 5
 *                                     with no special type
 *     Transcription Factor Binding Sites (TFBS) - peaks from transcription factor ChIP-seq
 *                   across a number of transcription factors and cell lines. Stored in bed 15
 *                   (or BED5+ factorSource format)
 *                   plus sourceTable with type factorSource */
 
#include "common.h"
#include "hash.h"
#include "jksql.h"
#include "obscure.h"
#include "hCommon.h"
#include "hdb.h"
#include "web.h"
#include "cart.h"
#include "trackDb.h"
#include "hui.h"
#include "hgc.h"
#include "encode/encodePeak.h"
#include "expRecord.h"
#include "bed6FloatScore.h"
#include "ra.h"
#include "jsHelper.h"
#include "factorSource.h"

static void printClusterTableHeader(struct slName *otherCols, 
	boolean withAbbreviation, boolean withDescription, boolean withSignal)
/* Print out header fields table of tracks in cluster */
{
webPrintLabelCell("#");
if (withSignal)
    webPrintLabelCell("signal");
if (withAbbreviation)
    webPrintLabelCell("abr");
struct slName *col;
for (col = otherCols; col != NULL; col = col->next)
    webPrintLabelCell(col->name);
if (withDescription)
    webPrintLabelCell("description");
webPrintLabelCell("more info");
}

static double getSignalAt(char *table, struct bed *cluster)
/* Get (average) signal from table entries that overlap cluster */
{
struct sqlConnection *conn = hAllocConn(database);
int count = 0;
double sum = 0;
if (sqlTableExists(conn, table))  // Table might be withdrawn from data thrash
    {
    int rowOffset;
    struct sqlResult *sr = hRangeQuery(conn, table, cluster->chrom, cluster->chromStart, 
	    cluster->chromEnd, NULL, &rowOffset);
    int signalCol = sqlFieldColumn(sr, "signalValue");
    if (signalCol < 0)
	internalErr();
    char **row;
    while ((row = sqlNextRow(sr)) != NULL)
	{
	count += 1;
	sum += sqlDouble(row[signalCol]);
	}
    sqlFreeResult(&sr);
    hFreeConn(&conn);
    }

if (count > 0)
    return sum/count;
else
    return 0;
}

static void printControlledVocabFields(char **row, int fieldCount, 
	struct slName *fieldList, char *vocabFile, struct hash *vocabHash)
/* Print out fields from row, linking them to controlled vocab if need be. */
{
int i;
struct slName *field;
for (i=0, field = fieldList; i<fieldCount; ++i, field = field->next)
    {
    char *fieldVal = row[i];
    if (vocabFile && hashLookup(vocabHash, field->name))
	{
	char *link = controlledVocabLink(vocabFile, "term", 
		fieldVal, fieldVal, fieldVal, "");
	webPrintLinkCell(link);
	}
    else
	webPrintLinkCell(fieldVal);
    }
}

struct hash *getVocabHash(char *fileName)
/* Get vocabulary term hash */
{
struct hash *hash = raTagVals(fileName, "type");
hashAdd(hash, "cellType", NULL);	/* Will the kludge never end, no, never! */
return hash;
}

static void printMetadataForTable(char *table)
/* If table exists, _and_ tdb associated with it exists, print out
 * a metadata link that expands on click.  Otherwise print "unavailable" */
{
webPrintLinkCellStart();
struct trackDb *tdb = hashFindVal(trackHash, table);
if (tdb == NULL)
    printf("%s info n/a", table);
else
    compositeMetadataToggle(database, tdb, "metadata", TRUE, FALSE);
webPrintLinkCellEnd();
}

static void queryInputTrackTable(struct dyString *query, char *inputTrackTable,
                                struct slName *fieldList)
/* Construct query in dyString to return contents of inputTrackTable ordered appropriately */
{
struct dyString *fields = dyStringNew(0);
struct slName *field;
sqlDyStringPrintf(query, "select tableName ");
for (field = fieldList; field != NULL; field = field->next)
    sqlDyStringPrintfFrag(fields, ",%s", field->name);
sqlDyStringPrintf(query, "%-s from %s", fields->string, inputTrackTable);
if (fieldList != NULL)
    // skip leading comma
    dyStringPrintf(query, " order by %s", fields->string+1);
dyStringFree(&fields);
}

static void printPeakClusterTableHits(struct bed *cluster, struct sqlConnection *conn,
	char *inputTrackTable, struct slName *fieldList, char *vocab)
/* Put out a lines in an html table that shows assayed sources that have hits in this
 * cluster, or if invert is set, that have misses. */
{
char *vocabFile = NULL;
struct hash *vocabHash = NULL;
if (vocab)
    {
    vocabFile = cloneFirstWord(vocab);
    vocabHash = getVocabHash(vocabFile);
    }

/* Make the SQL query to get the table and all other fields we want to show
 * from inputTrackTable. */
struct dyString *query = dyStringNew(0);
queryInputTrackTable(query, inputTrackTable, fieldList);

int displayNo = 0;
int fieldCount = slCount(fieldList);
struct sqlResult *sr = sqlGetResult(conn, query->string);
char **row;
while ((row = sqlNextRow(sr)) != NULL)
    {
    char *table = row[0];
    double signal = getSignalAt(table, cluster);
    if (signal != 0)
	{
	printf("</TR><TR>\n");
	webPrintIntCell(++displayNo);
	webPrintDoubleCell(signal);
	printControlledVocabFields(row+1, fieldCount, fieldList, vocabFile, vocabHash);
	printMetadataForTable(table);
	}
    }
sqlFreeResult(&sr);
freez(&vocabFile);
dyStringFree(&query);
}

static void printPeakClusterInputs(struct sqlConnection *conn,
	char *inputTrackTable, struct slName *fieldList, char *vocab)
/* Print out all input tables for clustering. */
{
char *vocabFile = NULL;
struct hash *vocabHash = NULL;
if (vocab)
    {
    vocabFile = cloneFirstWord(vocab);
    vocabHash = getVocabHash(vocabFile);
    }

/* Make the SQL query to get the table and all other fields we want to show
 * from inputTrackTable. */
struct dyString *query = dyStringNew(0);
queryInputTrackTable(query, inputTrackTable, fieldList);

int displayNo = 0;
int fieldCount = slCount(fieldList);
struct sqlResult *sr = sqlGetResult(conn, query->string);
char **row;
while ((row = sqlNextRow(sr)) != NULL)
    {
    printf("</TR><TR>\n");
    webPrintIntCell(++displayNo);
    printControlledVocabFields(row+1, fieldCount, fieldList, vocabFile, vocabHash);
    printMetadataForTable(row[0]);
    }


sqlFreeResult(&sr);
freez(&vocabFile);
dyStringFree(&query);
}

static char *factorSourceVocabLink(char *vocabFile, char *fieldName, char *fieldVal)
/* Add link to show controlled vocabulary entry for term.
 * Handles 'target' (factor) which is a special case, derived from Antibody entries */
{
char *vocabType = (sameString(fieldName, "target") || sameString(fieldName, "factor")) ?
                    "target" : "term";
return controlledVocabLink(vocabFile, vocabType, fieldVal, fieldVal, fieldVal, "");
}

static void printFactorSourceTableHits(struct factorSource *cluster, struct sqlConnection *conn,
	char *sourceTable, char *inputTrackTable, 
	struct slName *fieldList, boolean invert, char *vocab)
/* Put out a lines in an html table that shows assayed sources that have hits in this
 * cluster, or if invert is set, that have misses. */
{
char *vocabFile = NULL;
if (vocab)
    {
    vocabFile = cloneFirstWord(vocab);
    }

/* Make the monster SQL query to get all assays*/
struct dyString *query = dyStringNew(0);
sqlDyStringPrintf(query, "select %s.id,%s.name,%s.tableName", sourceTable, sourceTable, 
	inputTrackTable);
struct slName *field;
for (field = fieldList; field != NULL; field = field->next)
    sqlDyStringPrintf(query, ",%s.%s", inputTrackTable, field->name);
sqlDyStringPrintf(query, " from %s,%s ", inputTrackTable, sourceTable);
sqlDyStringPrintf(query, " where %s.source = %s.description", inputTrackTable, sourceTable);
sqlDyStringPrintf(query, " and factor='%s' order by %s.source", cluster->name, inputTrackTable);

int displayNo = 0;
int fieldCount = slCount(fieldList);
struct sqlResult *sr = sqlGetResult(conn, query->string);
char **row;
while ((row = sqlNextRow(sr)) != NULL)
    {
    int sourceId = sqlUnsigned(row[0]);
    boolean hit = FALSE;
    int i;
    double signal = 0.0;
    for (i=0; i<cluster->expCount; i++)
        {
        if (cluster->expNums[i] == sourceId)
            {
            hit = TRUE;
            signal = cluster->expScores[i];
            break;
            }
        }
    if (hit ^ invert)
        {
	printf("</TR><TR>\n");
	webPrintIntCell(++displayNo);
	if (!invert)
	    webPrintDoubleCell(signal);
	webPrintLinkCell(row[1]);
	int i = 0;
        // find position of CV metadata in field list
        int offset = 3;
        struct slName *field = fieldList;
	for (i=0; i<fieldCount && field != NULL; ++i, field = field->next)
	    {
	    char *fieldVal = row[i+offset];
	    if (vocab)
	        {
                char *link = cloneString(factorSourceVocabLink(vocabFile, field->name, fieldVal));
		webPrintLinkCell(link);
		}
	    else
		webPrintLinkCell(fieldVal);
	    }
	printMetadataForTable(row[2]);
	}
    }
sqlFreeResult(&sr);
freez(&vocabFile);
dyStringFree(&query);
}

void doPeakClusterListItemsAssayed()
/* Put up a page that shows all experiments associated with a cluster track. */
{
struct trackDb *clusterTdb = tdbForTableArg();
cartWebStart(cart, database, "List of items assayed in %s", clusterTdb->shortLabel);
struct sqlConnection *conn = hAllocConn(database);

char *inputTableFieldDisplay = trackDbSetting(clusterTdb, "inputTableFieldDisplay");
webPrintLinkTableStart();
if (inputTableFieldDisplay)
    {
    struct slName *fieldList = stringToSlNames(inputTableFieldDisplay);
    printClusterTableHeader(fieldList, FALSE, FALSE, FALSE);
    char *vocab = trackDbSetting(clusterTdb, "controlledVocabulary");
    char *inputTrackTable = trackDbRequiredSetting(clusterTdb, "inputTrackTable");
    printPeakClusterInputs(conn, inputTrackTable, fieldList, vocab);
    }
else
    errAbort("Missing required trackDb setting %s for track %s", "inputTableFieldDisplay", 
                clusterTdb->track);
webPrintLinkTableEnd();
hFreeConn(&conn);
}

void doPeakClusters(struct trackDb *tdb, char *item)
/* Display detailed info about a cluster of DNase peaks from other tracks. */
{
int start = cartInt(cart, "o");
char *table = tdb->table;
int rowOffset = hOffsetPastBin(database, seqName, table);
char query[256];
struct sqlResult *sr;
char **row;
struct bed *cluster = NULL;
struct sqlConnection *conn = hAllocConn(database);

cartWebStart(cart, database, "%s item details", tdb->shortLabel);
sqlSafef(query, sizeof(query),
	"select * from %s where  name = '%s' and chrom = '%s' and chromStart = %d",
	table, item, seqName, start);
sr = sqlGetResult(conn, query);
row = sqlNextRow(sr);
if (row != NULL)
    cluster = bedLoadN(row+rowOffset, 5);
sqlFreeResult(&sr);

if (cluster != NULL)
    {
    /* Get list of subgroups to display */
    char *inputTableFieldDisplay = trackDbSetting(tdb, "inputTableFieldDisplay");
    if (inputTableFieldDisplay != NULL)
        {
	struct slName *fieldList = stringToSlNames(inputTableFieldDisplay);
	char *vocab = trackDbSetting(tdb, "controlledVocabulary");
	char *inputTrackTable = trackDbRequiredSetting(tdb, "inputTrackTable");

	/* Print out some information about the cluster overall. */
	printf("<B>Items in Cluster:</B> %s of %d<BR>\n", cluster->name, 
	    sqlRowCount(conn, sqlCheckIdentifier(inputTrackTable)));
	printf("<B>Cluster Score (out of 1000):</B> %d<BR>\n", cluster->score);
	printPos(cluster->chrom, cluster->chromStart, cluster->chromEnd, NULL, TRUE, NULL);

	/* In a new section put up list of hits. */
	webNewSection("List of Items in Cluster");
	webPrintLinkTableStart();
	printClusterTableHeader(fieldList, FALSE, FALSE, TRUE);
	printPeakClusterTableHits(cluster, conn, inputTrackTable, fieldList, vocab);
	}
    else
	errAbort("Missing required trackDb setting %s for track %s",
	    "inputTableFieldDisplay", tdb->track);
    webPrintLinkTableEnd();
    }
printf("<A HREF=\"%s&g=htcListItemsAssayed&table=%s\" TARGET_blank>", hgcPathAndSettings(),
	tdb->track);
printf("List all items assayed");
printf("</A><BR>\n");
webNewSection("Track Description");
printTrackHtml(tdb);
hFreeConn(&conn);
}

void doClusterMotifDetails(struct sqlConnection *conn, struct trackDb *tdb, 
                                struct factorSource *cluster)
/* Display details about TF binding motif(s) in cluster */
{
char *motifTable = trackDbSetting(tdb, "motifTable");         // localizations
char *motifPwmTable = trackDbSetting(tdb, "motifPwmTable");   // PWM used to draw sequence logo
char *motifMapTable = trackDbSetting(tdb, "motifMapTable");   // map target to motif
char *motifName = cluster->name;         /* default to same as target */
struct dnaMotif *motif = NULL;
struct dnaSeq **seqs = NULL;
struct bed6FloatScore *hits = NULL;
char **row;
#ifdef SHOW_MAX_SCORE
struct sqlResult *sr;
#endif
char query[256], buf[256];

if (motifTable != NULL && sqlTableExists(conn, motifTable))
    {
    struct sqlResult *sr;
    int rowOffset;
    char where[256];

    if (motifMapTable != NULL && sqlTableExists(conn, motifMapTable))
        {
        sqlSafef(query, sizeof(query),
                "select motif from %s where target = '%s'", motifMapTable, cluster->name);
        // TODO: perhaps sqlQuickString ?
        motifName = sqlQuickQuery(conn, query, buf, sizeof(buf));
        if (motifName == NULL)
            return;
        }
    #define HIGHEST_SCORING
    #ifdef HIGHEST_SCORING
    sqlSafefFrag(where, sizeof(where), "name = '%s' order by score desc", motifName);
    #else
    sqlSafefFrag(where, sizeof(where), "name = '%s'", motifName);
    #endif
    sr = hRangeQuery(conn, motifTable, cluster->chrom, cluster->chromStart,
                     cluster->chromEnd, where, &rowOffset);
    #ifdef HIGHEST_SCORING
    if ((row = sqlNextRow(sr)) != NULL)
    #else
    while ((row = sqlNextRow(sr)) != NULL)
    #endif
        {
        struct bed6FloatScore *hit = NULL;
        AllocVar(hit);
        hit->chromStart = sqlUnsigned(row[rowOffset + 1]);
        hit->chromEnd = sqlUnsigned(row[rowOffset + 2]);
        hit->score = sqlFloat(row[rowOffset + 4]);
        hit->strand[0] = row[rowOffset + 5][0];
        slAddHead(&hits, hit);
        }
    sqlFreeResult(&sr);
    }
if (hits == NULL)
    {
    // Maintain table layout
    webNewEmptySection();
    return;
    }

int hitCount = 0;
if (motifPwmTable != NULL && sqlTableExists(conn, motifPwmTable))
    {
    motif = loadDnaMotif(motifName, motifPwmTable);
    }
struct bed6FloatScore *hit = NULL;
int i;
seqs = needMem(sizeof(struct dnaSeq *) * slCount(hits));
char posLink[1024];
hitCount = slCount(hits);

webNewSection("Canonical Motif in Cluster");

#ifdef SHOW_MAX_SCORE
float maxScore = -1;
sqlSafef(query, sizeof(query), 
    "select max(score) from %s where name = '%s'", motifTable, motifName);
sr = sqlGetResult(conn, query);
if ((row = sqlNextRow(sr)) != NULL)
    {
    if(!isEmpty(row[0]))
        {
        maxScore = sqlFloat(row[0]);
        }
    }
sqlFreeResult(&sr);
#endif

for (hit = hits, i = 0; hit != NULL; hit = hit->next, i++)
    {
    struct dnaSeq *seq = hDnaFromSeq(database, 
        seqName, hit->chromStart, hit->chromEnd, dnaLower);
    if(hit->strand[0] == '-')
        reverseComplement(seq->dna, seq->size);
    seqs[i] = seq;
    // TODO: move to hgc.c (with other pos printers)
    safef(posLink, sizeof(posLink),"<a href=\"%s&db=%s&position=%s%%3A%d-%d\">%s:%d-%d</a>",
            hgTracksPathAndSettings(), database, 
                cluster->chrom, hit->chromStart+1, hit->chromEnd,
                cluster->chrom, hit->chromStart+1, hit->chromEnd);
    printf("<b>Motif Name:</b>  %s<br>\n", motifName);
    printf("<b>Motif Score");
    if (hitCount > 1)
        {
        printf("#%d", i + 1);
        #ifdef SHOW_MAX_SCORE
        printf(":</b>  %.2f (%s max: %.2f) at %s on <b>%c</font></b> strand<br>", 
            hit->score, cluster->name, maxScore, posLink, (int)hit->strand[0]);
        #else
        printf(":</b>  %.2f at %s on <b>%c</font></b> strand<br>", 
            hit->score, posLink, (int)hit->strand[0]);
        #endif
        }
    else
        {
        #ifdef SHOW_MAX_SCORE
        printf(":</b>  %.2f (%s max: %.2f)<br>\n", hit->score, cluster->name, maxScore);
        #else
        printf(":</b>  %.2f<br>\n", hit->score);
        #endif
        printf("<b>Motif Position:</b> %s<br>\n", posLink);
        printf("<b>Motif Strand:</b> %c<br>\n", (int)hit->strand[0]);
        }
    }
if (seqs != NULL && motif != NULL)
    {
    motifLogoAndMatrix(seqs, hitCount, motif);
    }
}

void doFactorSource(struct sqlConnection *conn, struct trackDb *tdb, char *item, int start)
/* Display detailed info about a cluster of TFBS peaks from other tracks. */
{
int rowOffset = hOffsetPastBin(database, seqName, tdb->table);
char **row;
struct sqlResult *sr;
char query[256];

sqlSafef(query, sizeof(query),
	"select * from %s where name = '%s' and chrom = '%s' and chromStart = %d",
	tdb->table, item, seqName, start);
sr = sqlGetResult(conn, query);
row = sqlNextRow(sr);
struct factorSource *cluster = NULL;
if (row != NULL)
    cluster = factorSourceLoad(row + rowOffset);
sqlFreeResult(&sr);

if (cluster == NULL)
    errAbort("Error loading cluster from track %s", tdb->track);

char *sourceTable = trackDbRequiredSetting(tdb, "sourceTable");

char *factorLink = cluster->name;
char *vocab = trackDbSetting(tdb, "controlledVocabulary");
if (vocab != NULL)
    {
    char *file = cloneFirstWord(vocab);
    factorLink = controlledVocabLink(file, "term", factorLink, factorLink, factorLink, "");
    }
printf("<B>Factor:</B> %s<BR>\n", factorLink);
printf("<B>Cluster Score (out of 1000):</B> %d<BR>\n", cluster->score);
printPos(cluster->chrom, cluster->chromStart, cluster->chromEnd, NULL, TRUE, NULL);


/* Get list of tracks we'll look through for input. */
char *inputTrackTable = trackDbRequiredSetting(tdb, "inputTrackTable");
sqlSafef(query, sizeof(query), 
    "select tableName from %s where factor='%s' order by source", inputTrackTable, 
    cluster->name);

/* Next do the lists of hits and misses.  We have the hits from the non-zero signals in
 * cluster->expScores.  We need to figure out the sources actually assayed though
 * some other way.  We'll do this by one of two techniques. */
char *inputTableFieldDisplay = trackDbSetting(tdb, "inputTableFieldDisplay");
if (inputTableFieldDisplay != NULL)
    {
    struct slName *fieldList = stringToSlNames(inputTableFieldDisplay);
    char *vocab = trackDbSetting(tdb, "controlledVocabulary");

    /* In a new section put up list of hits. */
    webNewSection("Assays for %s in Cluster", cluster->name);
    webPrintLinkTableStart();
    printClusterTableHeader(fieldList, TRUE, FALSE, TRUE);
    printFactorSourceTableHits(cluster, conn, sourceTable, 
            inputTrackTable, fieldList, FALSE, vocab);
    webPrintLinkTableEnd();

    webNewSectionHeaderStart(TRUE);
    char sectionTitle[128];
    safef(sectionTitle, 
            sizeof(sectionTitle),"Assays for %s Without Hits in Cluster", cluster->name);
    jsBeginCollapsibleSectionOldStyle(cart, tdb->track, "cellNoHits", sectionTitle, FALSE);
    webNewSectionHeaderEnd();
    webPrintLinkTableStart();
    printClusterTableHeader(fieldList, TRUE, FALSE, FALSE);
    printFactorSourceTableHits(cluster, conn, sourceTable, 
            inputTrackTable, fieldList, TRUE, vocab);
    webPrintLinkTableEnd();
    jsEndCollapsibleSection();
    }
else
    {
    errAbort("Missing required trackDb setting %s for track %s",
        "inputTableFieldDisplay", tdb->track);
    }
webNewSectionHeaderStart(TRUE);
jsBeginCollapsibleSectionOldStyle(cart, tdb->track, "cellSources", "Cell Abbreviations", FALSE);
webNewSectionHeaderEnd();
hPrintFactorSourceAbbrevTable(conn, tdb);
jsEndCollapsibleSection();

doClusterMotifDetails(conn, tdb, cluster);
}
