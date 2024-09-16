#include <stdbool.h>
#include "zippo.h"
#include "unzip/unzip.h"
#include "yxml.h"

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

int32_t listFiles(void) {
	pd->system->logToConsole("Listing files...");
	pd->file->listfiles(".", ListFilesCallback, 0, 0);
	return 0;
}

static int readFromZip(lua_State* L) {
	const char *zipfilename = pd->lua->getArgString(1);
	const char *contentname = pd->lua->getArgString(2);
	// Create a variable to store the contents of the file
	char fileContents[10000];

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

		// Initialize a pointer to hold the file contents
		char *fileContents = NULL;
		size_t fileSize = 0;
		size_t bufferSize = 256; // Initial buffer size
		char szTemp[256];
		int rc = 1; // Initial value to enter the loop

		// Read until we reach the end of the file
		while (rc > 0)
		{
			rc = unzReadCurrentFile(zHandle, szTemp, sizeof(szTemp));
			if (rc >= 0)
			{
				if (rc > 0)
				{
					// Reallocate memory to hold the new data
					char *newBuffer = realloc(fileContents, fileSize + rc + 1); // +1 for null terminator
					if (newBuffer == NULL)
					{
						pd->system->logToConsole("Memory allocation failed\n");
						free(fileContents); // Free the previously allocated memory
						fileContents = NULL;
						break;
					}
					
					fileContents = newBuffer;
					// Copy the read data into the new buffer space
					memcpy(fileContents + fileSize, szTemp, rc);
					fileSize += rc;
					fileContents[fileSize] = '\0'; // Null-terminate the string
				}
			}
			else
			{
				pd->system->logToConsole("Error reading from file\n");
				free(fileContents); // Free allocated memory on error
				fileContents = NULL;
				break;
			}
		}

		// At this point, fileContents contains the entire file
		if (fileContents != NULL)
		{
			// Print the file contents split line by line
			char *line = strtok(fileContents, "\n");
			while (line != NULL)
			{
				pd->system->logToConsole("%s", line);
				line = strtok(NULL, "\n");
			}
			// Use fileContents here
			free(fileContents);
		}

        pd->system->logToConsole("Total bytes read = %d (reading 256 bytes at a time)\n", i);
        rc = unzCloseCurrentFile(zHandle);
        unzClose(zHandle);
    }
	return 0;
}

typedef struct
{
	char *id;
	char *href;
} ManifestItem;

// Make an enum of relevant element names including MANIFEST and ITEM
typedef enum
{
	UNKNOWN,
	MANIFEST,
	ITEM
} ElementName;

const int MAX_STACK_SIZE = 10000;

static bool stackContains(ElementName* stack, int top, ElementName element) {
	for (int i = 0; i < top; i++) {
		if (stack[i] == element) {
			return true;
		}
	}
	return false;
}

static bool withinManifest(ElementName* stack, int top) {
	return stackContains(stack, top, MANIFEST);
}

static int readEpub(lua_State* L) {
	const char *zipfilename = pd->lua->getArgString(1);

	// Create a variable to store the contents of the file
	char fileContents[10000];

    listFiles();
    pd->system->logToConsole("Reading stuff from %s", zipfilename);
    int rc = 0;
    ZIPFILE zpf;
    unzFile zHandle = unzOpen(zipfilename, NULL, 0, &zpf, myOpen, myRead, mySeek, myClose);

    if (zHandle == NULL) {
        pd->system->logToConsole("Failed to open %s", zipfilename);
    } else {
        pd->system->logToConsole("We got a handle: %d", zHandle);
    }

    char szComment[256];
    rc = unzGetGlobalComment(zHandle, szComment, sizeof(szComment));
    if (rc == UNZ_OK) {
        pd->system->logToConsole("comment: %s", &szComment);
    } else {
        pd->system->logToConsole("bad comment %d", rc);
    }

	char *contentPath = "OEBPS/content.opf";
    rc = unzLocateFile(zHandle, contentPath, 2);

    if (rc != UNZ_OK) {
        pd->system->logToConsole("File %s not found within archive", contentPath);
        unzClose(zHandle);
        //return -1;
    } else {
        pd->system->logToConsole("file found");
        rc = unzOpenCurrentFile(zHandle); /* Try to open the file we want */
        if (rc != UNZ_OK) {
            pd->system->logToConsole("Error opening file = %d\n", rc);
            unzClose(zHandle);
            //return -1;
        }
        
		pd->system->logToConsole("File located within archive.\n");
        rc = 1;
        int i = 0;

		// Initialize a pointer to hold the file contents
		char *fileContents = NULL;
		size_t fileSize = 0;
		size_t bufferSize = 256; // Initial buffer size
		char szTemp[256];
		int rc = 1; // Initial value to enter the loop

		// Read until we reach the end of the file
		while (rc > 0) {
			rc = unzReadCurrentFile(zHandle, szTemp, sizeof(szTemp));
			if (rc >= 0) {
				if (rc > 0) {
					// Reallocate memory to hold the new data
					char *newBuffer = realloc(fileContents, fileSize + rc + 1); // +1 for null terminator
					if (newBuffer == NULL) {
						pd->system->logToConsole("Memory allocation failed\n");
						free(fileContents); // Free the previously allocated memory
						fileContents = NULL;
						break;
					}
					
					fileContents = newBuffer;
					// Copy the read data into the new buffer space
					memcpy(fileContents + fileSize, szTemp, rc);
					fileSize += rc;
					fileContents[fileSize] = '\0'; // Null-terminate the string
				}
			} else {
				pd->system->logToConsole("Error reading from file\n");
				free(fileContents); // Free allocated memory on error
				fileContents = NULL;
				break;
			}
		}

		// At this point, fileContents contains the entire file
		if (fileContents != NULL) {
			// Print the file contents split line by line
			char *line = strtok(fileContents, "\n");
			while (line != NULL) {
				// pd->system->logToConsole("%s", line);
				line = strtok(NULL, "\n");
			}

			// Terminate the file contents string with a null character
			fileContents[fileSize] = '\0';

			// Parse the XML file
			yxml_t x;
			yxml_init(&x, fileContents, fileSize);
			
			ElementName elementStack[10000] = {UNKNOWN};
			int elementStackTop = 0;

			ManifestItem *manifestItems = NULL;
			ManifestItem *currentManifestItem = NULL;
			// Store the current attribute value
			char *currentAttributeValue = NULL;
			for (int i = 0; i < fileSize; i++) {
				int r = yxml_parse(&x, fileContents[i]);
				while (r > 0) {
					switch (r) {
					case YXML_ELEMSTART:
						pd->system->logToConsole("Element start: %s", x.elem);
						if (strcmp(x.elem, "manifest") == 0) {
							elementStack[elementStackTop] = MANIFEST;
						} else if (strcmp(x.elem, "item") == 0 && withinManifest(elementStack, elementStackTop)) {
							elementStack[elementStackTop] = ITEM;
						} else {
							elementStack[elementStackTop] = UNKNOWN;
						}
							elementStackTop++;
						break;
					case YXML_ELEMEND:
						// Cannot use x.elem to determine closing element: https://code.blicky.net/yorhel/yxml/issues/7
						elementStackTop--;
						const char* elementNameStr = (elementStack[elementStackTop] == MANIFEST) ? "MANIFEST" :
													 (elementStack[elementStackTop] == ITEM) ? "ITEM" : "UNKNOWN";
						pd->system->logToConsole("Element end: %s", elementNameStr);
						break;
					case YXML_ATTRSTART:
						pd->system->logToConsole("Attribute start: %s", x.attr);
						break;
					case YXML_ATTREND:
						pd->system->logToConsole("Attribute end: %s", x.attr);
						// Print the attribute value
						pd->system->logToConsole("Attribute value: %s", currentAttributeValue);
						if (withinManifest(elementStack, elementStackTop)) {
							if (currentManifestItem == NULL) {
								pd->system->logToConsole("Current manifest item is NULL");
							} else if (strcmp(x.attr, "id") == 0) {
								currentManifestItem->id = currentAttributeValue;
								pd->system->logToConsole("Manifest item id: %s", currentManifestItem->id);
							} else if (strcmp(x.attr, "href") == 0) {
								currentManifestItem->href = currentAttributeValue;
								pd->system->logToConsole("Manifest item href: %s", currentManifestItem->href);
							}
						}
						// Clear the current attribute value
						free(currentAttributeValue);
						currentAttributeValue = NULL;
						break;
					case YXML_ATTRVAL:
						// pd->system->logToConsole("Attribute value part: %s", x.data);
						if (currentAttributeValue == NULL) {
							currentAttributeValue = malloc(strlen(x.data) + 1);
							strcpy(currentAttributeValue, x.data);
						} else {
							char *newAttributeValue = realloc(currentAttributeValue, strlen(currentAttributeValue) + strlen(x.data) + 1);
							if (newAttributeValue == NULL) {
								pd->system->logToConsole("Memory allocation failed");
							}
							strcat(newAttributeValue, x.data);
							currentAttributeValue = newAttributeValue;	
						}
						break;
					case YXML_CONTENT:
						// pd->system->logToConsole("Content: %s", x.data);
						break;
					default:
						break;
					}
					r = yxml_parse(&x, 0);
				}
			}
			pd->system->logToConsole("Parsed XML file");


			// Use fileContents here
			free(fileContents);
		}

        pd->system->logToConsole("Total bytes read = %d (reading 256 bytes at a time)\n", i);
        rc = unzCloseCurrentFile(zHandle);
        unzClose(zHandle);
    }
	return 0;
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
	{ "readEpub", readEpub },
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
