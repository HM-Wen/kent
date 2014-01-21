/* eapMonitor - Monitor jobs running through the pipeline.. */
#include "common.h"
#include "linefile.h"
#include "hash.h"
#include "options.h"
#include "portable.h"
#include "obscure.h"
#include "../../../../parasol/inc/jobResult.h"
#include "../../../../parasol/inc/paraMessage.h"
#include "../../encodeDataWarehouse/inc/encodeDataWarehouse.h"
#include "../../encodeDataWarehouse/inc/edwLib.h"
#include "eapLib.h"

/* Command line variables. */
char *clParaHost = NULL;
char *clDatabase = NULL;
char *clTable = NULL;

void usage()
/* Explain usage and exit. */
{
errAbort(
  "eapMonitor v1 - Monitor jobs running through the pipeline.\n"
  "usage:\n"
  "   eapMonitor command\n"
  "commands:\n"
  "   status - print overall pipeline activity\n"
  "   steps - print out information on each step\n"
  "   info - information about configuration\n"
  "   chill - remove jobs that haven't started from job table, but keep running ones going\n"
  "   cull N - remove jobs that have been running more than N days\n"
  "   scrounge [parasolId] jobs that DB shows as running but parasol doesn't get poked\n"
  "   err [parasolId] print info about either most recent error or error of given id#\n"
  "   errFile [parasolId] print stderr from most recent error or error of given id#\n"
  "   errList [days] [step] - print list of parasol IDs, and command lines of all error jobs\n"
  "options:\n"
  "   -database=<mysql database> - default %s\n"
  "   -table=<msqyl table> - default %s\n"
  "   -paraHost=<host name of paraHub> - default %s\n"
  , edwDatabase, eapJobTable, eapParaHost
  );
}

/* Command line validation table. */
static struct optionSpec options[] = {
   {"database", OPTION_STRING},
   {"table", OPTION_STRING},
   {"paraHost", OPTION_STRING},
   {NULL, 0},
};

struct results
/* Information about a parasol results file */
    {
    struct results *next;
    char *name;	    /* Symbolic name */
    char *pathName; /* may include a few slashes with the file name */
    struct slName *lineList;	/* List of contents line by line. */
    struct jobResult *jobList;	/* Beware not always set. */
    int jobCount;
    /* -- beware under here vars not always set - check pointers for null. */
    int runningCount;
    };

char *pathToResultsName(char *path)
/* Return just name from a path of form /long/dir/to/name/results . */
{
char *endPat = "/results";
if (!endsWith(path, endPat))
    errAbort("Expecting this to end with .results: %s", path);

/*  Turn /this/that/results in path to /this/that in beforeResults. */
int endLen = strlen(endPat);
int pathLen = strlen(path);
int headLen = pathLen - endLen;
char beforeResults[headLen+1];
memcpy(beforeResults, path, headLen);
beforeResults[headLen] = 0;

char step[PATH_LEN];
splitPath(beforeResults, NULL, step, NULL);
return cloneString(step);
}

struct jobResult *linesToJobResults(struct slName *lineList)
/* Convert from lines to jobResults without destroying lines. */
{
struct slName *line;
struct jobResult *jobList = NULL, *job;
for (line = lineList; line != NULL; line = line->next)
    {
    int bufLen = strlen(line->name)+1;
    char buf[bufLen];
    char *row[JOBRESULT_NUM_COLS];
    memcpy(buf, line->name, bufLen);
    int wordCount = chopLine(buf, row);
    if  (wordCount != JOBRESULT_NUM_COLS)
	internalErr();
    job = jobResultLoad(row);
    slAddHead(&jobList, job);
    }
slReverse(&jobList);
return jobList;
}

struct results *resultsNew(char *resultsPath)
/* Wrap a results structure around file located at path */
{
struct results *results;
AllocVar(results);
results->name = pathToResultsName(resultsPath);
results->pathName = cloneString(resultsPath);
results->lineList = readAllLines(resultsPath);
results->jobList = linesToJobResults(results->lineList);
return results;
}

void searchForResults(char *dir, struct results **retResults)
/* Look in current dir and all subdirs for results files. */
{
char resultsPath[PATH_LEN];
safef(resultsPath, sizeof(resultsPath), "%s/results", dir);
if (fileExists(resultsPath))
     {
     struct results *results = resultsNew(resultsPath);
     slAddHead(retResults, results);
     }
struct fileInfo *fi, *fiList = listDirX(dir, "*", TRUE);
for (fi = fiList; fi != NULL; fi = fi->next)
    {
    if (fi->isDir)
	searchForResults(fi->name, retResults);
    }
}


int countParaRunning(struct sqlConnection *conn, struct hash *parasolRunningHash, 
    struct hash *qHash)
/* Count up number of jobs in are table that Parasol thinks are currently running */
{
int count = 0;
char query[512];
sqlSafef(query, sizeof(query), "select * from %s where startTime > 0 and endTime = 0", clTable);
struct edwAnalysisJob *job, *jobList = edwAnalysisJobLoadByQuery(conn, query);
for (job = jobList; job != NULL; job = job->next)
    {
    char *step = eapStepFromCommandLine(job->commandLine);
    struct results *q = hashFindVal(qHash, step);
    if (q != NULL)
        q->runningCount += 1;
    else
        warn("%s not in qHash", step);
        
    if (hashLookup(parasolRunningHash, job->parasolId))
        {
	++count;
	}
    }
return count;
}

int countOldJobs(struct sqlConnection *conn, double days)
/* Return number of jobs older than given number of days old */
{
int seconds = days * 3600 * 24;
long long limit = edwNow() - seconds;
char query[512];
safef(query, sizeof(query), 
    "select count(*) from %s where startTime != 0 and startTime < %lld and endTime=0", 
    clTable, limit);
return sqlQuickNum(conn, query);
}

int printDaysOldJobs(struct sqlConnection *conn, int days)
/* Print info about job more than %d days old if any.  Return that count.  */
{
int jobCount = countOldJobs(conn, days);
if (jobCount > 0)
    printf("Jobs >%d day old:      %-4d\n", days, countOldJobs(conn, days));
return jobCount;
}

int resultsScore(const struct results *q)
{
return 100000 * q->runningCount + q->jobCount;
}

int resultsCmpScore(const void *va, const void *vb)
/* Compare to sort based on scoring function start. */
{
const struct results *a = *((struct results **)va);
const struct results *b = *((struct results **)vb);
return resultsScore(b) - resultsScore(a);
}


void doStatus()
/* Print out overall status */
{
struct results *q, *qList = NULL;
struct hash *qHash = hashNew(0);
searchForResults(eapParaQueues, &qList);
int qCount = 0;
long finishedJobs = 0;
for (q = qList; q != NULL; q = q->next)
    {
    ++qCount;
    hashAdd(qHash, q->name, q);
    q->jobCount = slCount(q->lineList);
    finishedJobs += q->jobCount;
    }

struct hash *runningHash = eapParasolRunningHash(clParaHost, NULL);
struct sqlConnection *conn = edwConnect();
int runningCount = countParaRunning(conn, runningHash, qHash);

// printf("Jobs finished: %ld\n", finishedJobs);
printf("Analysis steps:   %5d:", qCount);
slSort(&qList, resultsCmpScore);
int i;
q = qList;
for (i=0; i<3 && i<qCount; ++i)
    {
    if (i>0)
        printf(",");
    printf(" %s %d", q->name, q->runningCount);
    q = q->next;
    }
printf("\n");

char query[512];
printf("Jobs >12 hours old: %3d\n", countOldJobs(conn, 0.5));
printDaysOldJobs(conn, 1);
printDaysOldJobs(conn, 2);
printDaysOldJobs(conn, 3);
printDaysOldJobs(conn, 5);
printDaysOldJobs(conn, 10);

if (runningCount > 0)
    {
    sqlSafef(query, sizeof(query), "select min(startTime) from %s where startTime>0 and endTime=0",
	clTable);
    double oldestSeconds = edwNow() - sqlQuickNum(conn, query);
    printf("Oldest job:       %5.2f hours\n", oldestSeconds/(3600));
    }

printf("Jobs running:   %7d\n", runningCount);

sqlSafef(query, sizeof(query), "select count(*) from %s where startTime>0 and endTime=0", clTable);
int dbJobsPending = sqlQuickNum(conn, query);
printf("Jobs scheduled: %7d\n", dbJobsPending);

sqlSafef(query, sizeof(query), "select count(*) from %s where startTime=0", clTable);
int dbJobsQueued = sqlQuickNum(conn, query);
printf("Jobs queued:    %7d\n", dbJobsQueued);

sqlSafef(query, sizeof(query), "select max(endTime) from %s where returnCode = 0", clTable);
long long lastGoodTime = sqlQuickLongLong(conn, query);
printf("Last return ok:  %6.2f hours ago\n", (double)(edwNow() - lastGoodTime)/3600);

sqlSafef(query, sizeof(query), "select max(endTime) from %s where returnCode != 0", clTable);
long long lastCrashTime = sqlQuickLongLong(conn, query);
printf("Last crash:      %6.2f hours ago\n", (double)(edwNow() - lastCrashTime)/3600);

sqlSafef(query, sizeof(query), "select count(*) from %s where returnCode != 0", clTable);
int dbJobsCrashed = sqlQuickNum(conn, query);
printf("Jobs crashed:   %7d\n", dbJobsCrashed);

sqlSafef(query, sizeof(query), "select count(*) from %s where endTime > 0 and returnCode=0", 
    clTable);
int dbJobsGood = sqlQuickNum(conn, query);
printf("Jobs return ok: %7d\n", dbJobsGood);

}

void doChill()
/* Remove jobs we haven't gotten to yet */
{
struct sqlConnection *conn = sqlConnect(clDatabase);
char query[512];
safef(query, sizeof(query), "select count(*) from %s where startTime=0", clTable);
printf("Chilling %d jobs\n", sqlQuickNum(conn, query));
safef(query, sizeof(query), "delete from %s where startTime=0", clTable);
sqlUpdate(conn, query);
}

void doCull(double days)
/* Remove jobs that are older than a certain number of days. */
{
int seconds = days * 3600 * 24;
long long limit = edwNow() - seconds;
struct sqlConnection *conn = sqlConnect(clDatabase);
char query[512];
safef(query, sizeof(query), "select parasolId from %s where startTime < %lld and endTime=0", 
    clTable, limit);
struct slName *id, *idList = sqlQuickList(conn, query);
printf("Culling %d jobs\n", slCount(idList));
safef(query, sizeof(query), "delete from %s where startTime < %lld and endTime=0", 
    clTable, limit);
sqlUpdate(conn, query);
for (id = idList; idList != NULL; id = id->next)
    {
    char buf[256];
    safef(buf, sizeof(buf), "removeJob %s", id->name);
    pmHubSingleLineQuery(buf, clParaHost);
    }
}

void doInfo()
/* Print out configuration info. */
{
printf("Queue dir:     %s\n", eapParaQueues);
printf("Database:      %s\n", clDatabase);
printf("Jobs table:    %s\n", clTable);
printf("Parasol host:  %s\n", clParaHost);
}

struct jobResult *getRecentCrashed(struct jobResult *jobList, struct jobResult *bestSoFar)
/* Return most recently crashed from list that is more recent than bestSoFar (which may be NULL) */
{
struct jobResult *job;
for (job = jobList; job != NULL; job = job->next)
    {
    if (!WIFEXITED(job->status) || WEXITSTATUS(job->status) != 0)
        {
	if (bestSoFar == NULL)
	    bestSoFar = job;
	else
	    {
	    if (job->endTime > bestSoFar->endTime)
	         bestSoFar = job;
	    }
	}
    }
return bestSoFar;
}

char *copyRemoteToTemp(char *host, char *file)
/* Copy named file to our temp dir and return path to it.  Lazy routine
 * does nothing to make sure you don't overwrite things in temp dir. */
{
char dir[PATH_LEN], root[PATH_LEN], ext[PATH_LEN];
splitPath(file, dir, root, ext);
char tempPath[PATH_LEN];
safef(tempPath, sizeof(tempPath), "%s%s%s", eapTempDir, root, ext);
char command[3*PATH_LEN];
safef(command, sizeof(command), "scp %s:%s %s", host, file, tempPath);
mustSystem(command);
return cloneString(tempPath);
}

void printRemoteHeadTail(char *host, char *file, int headSize, int tailSize)
/* Fetch remote file, print head and tail, and then remove it. */
{
char *tempFile = copyRemoteToTemp(host, file);
struct slName *line, *lineList = readAllLines(tempFile);
int lineCount = slCount(lineList);
if (headSize + tailSize >= lineCount)
    {
    for (line = lineList; line != NULL; line = line->next)
        puts(line->name);
    }
else
    {
    int lineIx = 0;
    for (lineIx=0, line=lineList; lineIx < headSize;  ++lineIx, line = line->next)
        {
	puts(line->name);
	}
    int tailStart = lineCount - tailSize;
    printf("  ..........................................................................\n");
    for (;line != NULL; ++lineIx, line = line->next)
        {
	if (lineIx >= tailStart)
	    puts(line->name);
	}
    }
mustRemove(tempFile);
}

struct edwAnalysisJob *edwAnalysisJobFromParasolId(struct sqlConnection *conn, char *parasolId)
/* Return job matching parasol ID if any. */
{
char query[256];
sqlSafef(query, sizeof(query), "select * from %s where parasolId='%s'",
	clTable, parasolId);
return edwAnalysisJobLoadByQuery(conn, query);
}

struct jobResult *findJobOnList(struct jobResult *list, char *parasolId)
/* Return element on list matching parasolId, or NULL if none match. */
{
struct jobResult *job;
for (job = list; job != NULL; job = job->next)
    if (sameString(job->jobId, parasolId))
        return job;
return NULL;
}

struct jobResult *findJobInResults(struct results *resultsList, char *parasolId)
/* Return jobResult of given parasolId if it exists in resultsList */
{
struct results *q;
for (q = resultsList; q != NULL; q = q->next)
    {
    struct jobResult *jr = findJobOnList(q->jobList, parasolId);
    if (jr != NULL)
        return jr;
    }
return NULL;
}

struct jobResult *findCrashed(char *parasolId)
/* Find job with given parasol ID or if parasolID is null, most recently crashed job */
{
struct results *q, *qList = NULL;
struct jobResult *crashed = NULL;
searchForResults(eapParaQueues, &qList);
for (q = qList; q != NULL; q = q->next)
    {
    struct jobResult *jrList = q->jobList;
    if (parasolId)
        {
	crashed = findJobOnList(jrList, parasolId);
	if (crashed != NULL)
	    break;
	}
    else
	crashed = getRecentCrashed(jrList, crashed);
    }
return crashed;
}

void doErr(int argc, char **argv)
/* Print error stats, and specific info on a recent error */
{
char *parasolId = NULL;
if (argc > 0)
    parasolId = argv[0];
struct jobResult *crashed = findCrashed(parasolId);
if (crashed != NULL)
    {
    struct sqlConnection *conn = sqlConnect(clDatabase);
    struct edwAnalysisJob *job = edwAnalysisJobFromParasolId(conn, crashed->jobId);
    if (job != NULL)
	{
	printf("Command line: %s\n", job->commandLine);
	double timeAgo = edwNow() - crashed->endTime;
	printf("Crash time: %6.2g hours ago\n", timeAgo/3600);
	}
    else
        {
	printf("Warning:  parasol job id %s not found in %s\n", crashed->jobId, clTable);
	}
    printf("Parasol ID:   %s\n", crashed->jobId);
    printf("User ticks:   %d\n", crashed->usrTicks);
    printf("System ticks: %d\n", crashed->sysTicks);
    printf("Clock seconds: %d\n", crashed->endTime - crashed->startTime);
    printf("Host:         %s\n", crashed->host);
    printf("Status:       %5d\n", crashed->status);
    printf("Stderr file:  %s\n", crashed->errFile);
    printRemoteHeadTail(crashed->host, crashed->errFile, 8, 4);
    }
}

void doErrFile(int argc, char **argv)
/* Print out stderr file entirely */
{
char *parasolId = NULL;
if (argc > 0)
    parasolId = argv[0];
struct jobResult *crashed = findCrashed(parasolId);
if (crashed == NULL)
    errAbort("No most recent error");
char command[2*PATH_LEN];
safef(command, sizeof(command), "scp %s:%s /dev/stdout", crashed->host, crashed->errFile);
mustSystem(command);
}

void doErrList(int argc, char **argv)
/* Print list of parasol IDs, and command lines of all error jobs. */
{
/* Process command line */
double days = BIGNUM;
if (argc > 0)
    days = sqlDouble(argv[0]);
char *step = NULL;
if (argc > 1)
    step = argv[1];

/* Get finished job lists. */
struct results *qList = NULL;
searchForResults(eapParaQueues, &qList);

struct sqlConnection *conn = edwConnect();
char query[512];
sqlSafef(query, sizeof(query), 
    "select * from edwAnalysisJob where returnCode != 0 and endTime > %lld",
    edwNow() - (long long)(days * 3600 * 24));
struct edwAnalysisJob *job, *jobList = edwAnalysisJobLoadByQuery(conn, query);
for (job = jobList; job != NULL; job = job->next)
    {
    char *node = "n/a";
    struct jobResult *jr = findJobInResults(qList, job->parasolId);
    if (jr != NULL)
        node = jr->host;
    if (step != NULL && !sameOk(eapStepFromCommandLine(job->commandLine), step))
        continue;
    printf("%s\t%s\t%s\n", naForEmpty(job->parasolId), node, job->commandLine);
    }
}

boolean isSick(struct results *q)
/* Return TRUE if batch has been deemed sick */
{
char message[512];
safef(message, sizeof(message), "pstat2 %s %s", getUser(), q->pathName);
struct slName *line, *lineList = pmHubMultilineQuery(message, clParaHost);
boolean gotSick = FALSE;
for (line = lineList; line != NULL; line = line->next)
    {
    if (startsWith("Sick Batch:", line->name))
        {
	gotSick = TRUE;
	break;
	}
    }
slFreeList(&lineList);
return gotSick;
}

char *glueFromPath(char *path)
/* Given path to parasol queue, return corresponding glue script name.
 * FreeMem the results of this when done. */
{
if (!startsWith( eapParaQueues, path))
    errAbort("%s does not start with %s", path, eapParaQueues);
char *local = path + strlen(eapParaQueues) + 1;
char dir[PATH_LEN];
splitPath(local, dir, NULL, NULL);
int dirLen = strlen(dir);
assert(dirLen > 0);
dir[dirLen-1] = 0;  // Strip trailing '/'
return cloneString(dir);
}

char *glueFromCommandLine(char *commandLine)
/* Parse out the glue part of the command line. */
{
int bufSize = strlen(commandLine)+1;
char buf[bufSize];
strcpy(buf, commandLine);
char *line = buf;
char *edwCdJob = nextWord(&line);
char *glue = nextWord(&line);
if (glue == NULL || !sameString(edwCdJob, "edwCdJob"))
    errAbort("Oops, command line changed away from edwCdJob");
return cloneString(glue);
}

int countRunning(struct sqlConnection *conn, struct results *q, struct hash *pjobHash)
/* Count up the number of jobs in pjobList that are associated with q */
{
char *glue = glueFromPath(q->pathName);
char query[PATH_LEN*2];
sqlSafef(query, sizeof(query), "select * from %s where startTime > 0 and endTime = 0", clTable);
struct edwAnalysisJob *job, *jobList = edwAnalysisJobLoadByQuery(conn, query);
int runningCount = 0;
for (job = jobList; job != NULL; job = job->next)
    {
    struct paraPstat2Job *pjob = hashFindVal(pjobHash, job->parasolId);
    if (pjob != NULL)
         {
	 char *commandGlue = glueFromCommandLine(job->commandLine);
	 if (sameString(commandGlue, glue))
	     {
	     ++runningCount;
	     }
	 freez(&commandGlue);
	 }
    }
freez(&glue);
return runningCount;
}

void doSteps(int argc, char **argv)
/* Show activity of various analysis steps */
{
struct results *q, *qList = NULL;
struct sqlConnection *conn = sqlConnect(clDatabase);
searchForResults(eapParaQueues, &qList);
struct paraPstat2Job *pjobList = NULL;
struct hash *pjobHash = eapParasolRunningHash(clParaHost, &pjobList);

printf("#stat finish run results\n");
for (q = qList; q != NULL; q = q->next)
    {
    char *code = (isSick(q) ? "sick" : "good");
    int runCount = countRunning(conn, q, pjobHash);
    printf("%s %6d %3d %s\n", code, slCount(q->lineList), runCount, q->pathName);
    }
}

void doScrounge(int argc, char **argv)
/* scrounge [parasolId] - jobs that DB shows as running but parasol doesn't get poked */
{
/* Process rest of command line */
char *parasolId = NULL;
if (argc > 0)
    parasolId = argv[0];

/* Make a list and hash of outstanding job from db point of view */
struct sqlConnection *conn = sqlConnect(clDatabase);
char query[512];
sqlSafef(query, sizeof(query), "select * from %s where startTime > 0 and endTime = 0", clTable);
struct edwAnalysisJob *job, *jobList = edwAnalysisJobLoadByQuery(conn, query);
struct hash *jobHash = hashNew(0);
for (job = jobList; job != NULL; job = job->next)
    hashAdd(jobHash, job->parasolId, job);
verbose(1, "Have %d pending jobs with parasol\n", slCount(jobList));

/* Make a list/hash of jobs currently running */
struct paraPstat2Job *pJob, *pJobList = NULL;
struct hash *pJobHash = eapParasolRunningHash(clParaHost, &pJobList);
for (pJob = pJobList; pJob != NULL; pJob = pJob->next)
    {
    hashAdd(pJobHash, pJob->parasolId, pJob);
    }

/* Loop through database job list.  If it isn't on the running list then assume it's a lost
 * sole and mark it as succeeded at current time.... */
int scroungeCount = 0;
if (parasolId)
    {
    sqlSafef(query, sizeof(query), "update %s set endTime=%lld where parasolId='%s'",
	clTable, edwNow(), parasolId);
    sqlUpdate(conn, query);
    scroungeCount = 1;
    }
else
    {
    for (job = jobList; job != NULL; job = job->next)
	{
	if (!hashLookup(pJobHash, job->parasolId))
	    {
	    sqlSafef(query, sizeof(query), "update %s set endTime=%lld where id=%u",
		clTable, edwNow(), job->id);
	    sqlUpdate(conn, query);
	    ++scroungeCount;
	    }
	}
    }
printf("Scrounged %d - use eapFinish and it will find them or doom them\n", scroungeCount);
}


void eapMonitor(char *command, int argc, char **argv)
/* eapMonitor - Monitor jobs running through the pipeline.. */
{
if (sameString(command, "status"))
    {
    doStatus();
    }
else if (sameString(command, "chill"))
    {
    doChill();
    }
else if (sameString(command, "cull"))
    {
    if (argc != 1)
         usage();
    double days = sqlDouble(argv[0]);
    doCull(days);
    }
else if (sameString(command, "info"))
    {
    doInfo();
    }
else if (sameString(command, "err"))
    {
    doErr(argc, argv);
    }
else if (sameString(command, "errFile"))
    {
    doErrFile(argc, argv);
    }
else if (sameString(command, "errList"))
    {
    doErrList(argc, argv);
    }
else if (sameString(command, "steps"))
    {
    doSteps(argc, argv);
    }
else if (sameString(command, "scrounge"))
    {
    doScrounge(argc, argv);
    }
else
    {
    errAbort("Unrecognized command %s", command);
    }
}

int main(int argc, char *argv[])
/* Process command line. */
{
optionInit(&argc, argv, options);
if (argc < 2)
    usage();
clParaHost = optionVal("paraHost", eapParaHost);
clDatabase = optionVal("database", edwDatabase);
clTable = optionVal("table", eapJobTable);
eapMonitor(argv[1], argc-2, argv+2);
return 0;
}
