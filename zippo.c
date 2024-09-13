#include "zippo.h"
#include "unzip/unzip.h"

static PlaydateAPI* pd = NULL;

typedef struct
{
	int count;
	int* data;
} Zippo;

static int zippo_newobject(lua_State* L)
{
	int count = pd->lua->getArgInt(1);
	
	if ( count <= 0 )
		return 0;

	Zippo* zippo = pd->system->realloc(NULL, sizeof(Zippo));
	zippo->count = count;
	zippo->data = pd->system->realloc(NULL, sizeof(int) * count);
	pd->lua->pushObject(zippo, "zippo", 0);
	return 1;
}

static int zippo_gc(lua_State* L)
{
	Zippo* zippo = pd->lua->getArgObject(1, "zippo", NULL);
	
	if ( zippo != NULL )
	{
		pd->system->realloc(zippo->data, 0);
		pd->system->realloc(zippo, 0);
	}
	
	return 0;
}

static int zippo_index(lua_State* L)
{
	// we first need to check if the requested member is defined in the
	// metatable, otherwise we can't call other functions in this class
	
	if ( pd->lua->indexMetatable() )
		return 1;
	
	Zippo* zippo = pd->lua->getArgObject(1, "zippo", NULL);
	int idx = pd->lua->getArgInt(2);
	
	if ( zippo != NULL && idx > 0 && idx <= zippo->count )
	{
		pd->lua->pushInt(zippo->data[idx-1]);
		return 1;
	}
	else
		return 0;
}

static int zippo_newindex(lua_State* L)
{
	Zippo* zippo = pd->lua->getArgObject(1, "zippo", NULL);
	int idx = pd->lua->getArgInt(2);
	
	if ( pd->lua->getArgType(3, NULL) != kTypeInt )
	{
		pd->system->error("zippo only accepts integer types");
		return 0;
	}
	
	if ( zippo != NULL && idx > 0 && idx <= zippo->count )
		zippo->data[idx-1] = pd->lua->getArgInt(3);

	return 0;
}

static int zippo_len(lua_State* L)
{
	Zippo* zippo = pd->lua->getArgObject(1, "zippo", NULL);
	
	if ( zippo != NULL )
	{
		pd->lua->pushInt(zippo->count);
		return 1;
	}
	else
		return 0;
}

// while we're here we can add some utility functions..
#include <limits.h>

static int zippo_getmin(lua_State* L)
{
	Zippo* zippo = pd->lua->getArgObject(1, "zippo", NULL);
	
	if ( zippo == NULL )
		return 0;

	int min = zippo->data[0];
	int pos = 0;

	for ( int i = 1; i < zippo->count; ++i )
	{
		if ( zippo->data[i] < min )
		{
			min = zippo->data[i];
			pos = i;
		}
	}
	
	pd->lua->pushInt(min);
	pd->lua->pushInt(pos+1);
	return 2;
}

static int zippo_getmax(lua_State* L)
{
	Zippo* zippo = pd->lua->getArgObject(1, "zippo", NULL);
	
	if ( zippo == NULL )
		return 0;
	
	int max = zippo->data[0];
	int pos = 0;

	for ( int i = 1; i < zippo->count; ++i )
	{
		if ( zippo->data[i] > max )
		{
			max = zippo->data[i];
			pos = i;
		}
	}
	
	pd->lua->pushInt(max);
	pd->lua->pushInt(pos+1);
	return 2;
}

static int zippo_getavg(lua_State* L)
{
	Zippo* zippo = pd->lua->getArgObject(1, "zippo", NULL);
	long long sum = 0;
	
	for ( int i = 0; i < zippo->count; ++i )
		sum += zippo->data[i];
	
	pd->lua->pushInt(sum/zippo->count);
	return 1;
}

void *myOpen(const char *filename, int32_t *size)
{
    pd->system->logToConsole("Attempting to open");
    size_t filesize;
    SDFile *myfile = pd->file->open(filename, 1);
    if (myfile)
    {
        pd->file->seek(myfile, 0, SEEK_END);
        filesize = pd->file->tell(myfile);
        pd->file->seek(myfile, 0, SEEK_SET);
        *size = (int32_t)filesize;
    }
    pd->system->logToConsole("myfile handle: %d", myfile);
    return (void *)myfile;
}

void myTest(void)
{
	pd->system->logToConsole("Test function called");
}

void myClose(void *p)
{
    ZIPFILE *pzf = (ZIPFILE *)p;
    SDFile *f = (SDFile *)pzf->fHandle;
    pd->file->close(f);
    pd->system->logToConsole("File closed on handle: %d", f);
}

int32_t myRead(void *p, uint8_t *buffer, int32_t length)
{
    ZIPFILE *pzf = (ZIPFILE *)p;
    if (!pzf)
        return 0;
    SDFile *f = (SDFile *)pzf->fHandle;
    return (int32_t)pd->file->read(f, buffer, length);
}

int32_t mySeek(void *p, int32_t position, int iType)
{
    ZIPFILE *pzf = (ZIPFILE *)p;
    if (!pzf)
        return 0;
    SDFile *f = (SDFile *)pzf->fHandle;
    return pd->file->seek(f, position, iType);
}

static void ListFilesCallback(const char *name, void *userdata) {
    pd->system->logToConsole("File: %s", name);
}

int32_t listFiles()
{
	pd->system->logToConsole("Listing files...");
	pd->file->listfiles(".", ListFilesCallback, 0, 0);
	return 0;
}

void readFromZip(lua_State* L) {
	const char *zipfilename = pd->lua->getArgString(1);
	const char *contentname = pd->lua->getArgString(2);

    listFiles();
    pd->system->logToConsole("Reading stuff from %s", zipfilename);
    int rc = 0;
    ZIPFILE zpf;
    unzFile zHandle = unzOpen(zipfilename, NULL, 0, &zpf, myOpen, myRead, mySeek, myClose);

    if (zHandle == NULL)
    {
        pd->system->logToConsole("Failed to open");
    }
    else
    {
        pd->system->logToConsole("We got a handle: %d", zHandle);
    }
    char szComment[256];
    rc = unzGetGlobalComment(zHandle, szComment, sizeof(szComment));
    if (rc == UNZ_OK)
    {
        pd->system->logToConsole("comment: %s", &szComment);
    }
    else
    {
        pd->system->logToConsole("bad comment %d", rc);
    }

    rc = unzLocateFile(zHandle, contentname, 2);
    //rc = unzLocateFile(zHandle, "testfile", 2);

    if (rc != UNZ_OK) /* Report the file not found */
    {
        pd->system->logToConsole("file %s not found within archive", contentname);
        unzClose(zHandle);
        //return -1;
    }
    else
    {
        pd->system->logToConsole("file found");
        rc = unzOpenCurrentFile(zHandle); /* Try to open the file we want */
        if (rc != UNZ_OK)
        {
            pd->system->logToConsole("Error opening file = %d\n", rc);
            unzClose(zHandle);
            //return -1;
        }
        pd->system->logToConsole("File located within archive.\n");
        rc = 1;
        int i = 0;

        char szTemp[256];
        while (rc > 0 && i <= 1024) // just read the first 1024 bytes
        {
            rc = unzReadCurrentFile(zHandle, szTemp, sizeof(szTemp));
            if (rc >= 0)
            {
                i += rc;
                if (rc > 0)
                {
                    pd->system->logToConsole("%s", szTemp);
                }
            }
            else
            {
                pd->system->logToConsole("Error reading from file\n");
                break;
            }
        }
        pd->system->logToConsole("Total bytes read = %d (reading 256 bytes at a time)\n", i);
        rc = unzCloseCurrentFile(zHandle);
        unzClose(zHandle);
    }
}


static const lua_reg zippoLib[] =
{
	{ "new", 		zippo_newobject },
	{ "__gc",		zippo_gc },
	{ "__index", 	zippo_index },
	{ "__newindex",	zippo_newindex },
	{ "__len",		zippo_len },
	{ "getMinimum", zippo_getmin },
	{ "getMaximum", zippo_getmax },
	{ "getAverage", zippo_getavg },
	{ "readFromZip", readFromZip },
	{ "myTest", myTest },
	{ NULL, NULL }
};

void registerZippo(PlaydateAPI* playdate)
{
	pd = playdate;
	
	const char* err;

	pd->system->logToConsole("Registering Zippo class");
	
	if ( !pd->lua->registerClass("zippo", zippoLib, NULL, 0, &err) )
		pd->system->logToConsole("%s:%i: registerClass failed, %s", __FILE__, __LINE__, err);
}
