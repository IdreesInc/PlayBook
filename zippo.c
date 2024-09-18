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

static void listFilesCallback(const char *name, void *userdata) {
    pd->system->logToConsole("File: %s", name);
}

int32_t listFiles(void) {
	pd->system->logToConsole("Listing files...");
	pd->file->listfiles(".", listFilesCallback, 0, 0);
	return 0;
}

static debugLog(const char *message) {
	pd->system->logToConsole(message);
	SDFile* file = pd->file->open("log.txt", kFileAppend);
	if (file) {
		pd->file->write(file, message, strlen(message));
		pd->file->write(file, "\n", 1);
		pd->file->close(file);
	} else {
		pd->system->logToConsole("Failed to open file for writing");
	}
}

typedef struct
{
	char id[256];
	char href[256];
} ManifestItem;

// Make an enum of relevant element names including MANIFEST and MANIFEST_ITEM
typedef enum
{
	UNKNOWN,
	MANIFEST,
	MANIFEST_ITEM,
	SPINE,
	SPINE_ITEM
} ElementName;

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

static bool withinSpine(ElementName* stack, int top) {
	return stackContains(stack, top, SPINE);
}

static char** getContentPaths(char *opfContents, size_t fileSize, int *contentPathCount) {
	debugLog("Alright, here we go");
	// Parse the XML file
	yxml_t x;
	yxml_init(&x, opfContents, fileSize);
	
	ElementName elementStack[1000] = {UNKNOWN};
	int elementStackTop = 0;

	// Store items declared in the manifest for later lookup
	ManifestItem manifestItems[1000];
	int manifestItemCount = 0;
	ManifestItem currentManifestItem;
	// Store spine items
	char spineItems[1000][256];
	int spineItemCount = 0;
	char currentSpineIdref[256];
	// Store the current attribute value
	char *currentAttributeValue = NULL;
	debugLog("Starting parse of XML file");
	int count = 0;
	for (int i = 0; i < fileSize; i++) {
		int parseCode = yxml_parse(&x, opfContents[i]);
		while (parseCode > 0) {
			pd->system->logToConsole("Parse code: %d", parseCode);
			// switch (parseCode) {
			// case YXML_ELEMSTART:
			// 	pd->system->logToConsole("Element start: %s", x.elem);
			// 	if (strcmp(x.elem, "manifest") == 0) {
			// 		elementStack[elementStackTop] = MANIFEST;
			// 	} else if (strcmp(x.elem, "item") == 0 && withinManifest(elementStack, elementStackTop)) {
			// 		elementStack[elementStackTop] = MANIFEST_ITEM;
			// 	} else if (strcmp(x.elem, "spine") == 0) {
			// 		elementStack[elementStackTop] = SPINE;
			// 	} else if (strcmp(x.elem, "itemref") == 0 && withinSpine(elementStack, elementStackTop)) {
			// 		elementStack[elementStackTop] = SPINE_ITEM;
			// 	} else {
			// 		elementStack[elementStackTop] = UNKNOWN;
			// 	}
			// 	elementStackTop++;
			// 	break;
			// case YXML_ELEMEND:
			// 	// Cannot use x.elem to determine closing element: https://code.blicky.net/yorhel/yxml/issues/7
			// 	if (elementStackTop == 0) {
			// 		pd->system->logToConsole("ERROR: Element stack is empty and yet pop was attempted");
			// 	} else {
			// 		elementStackTop--;
			// 		if (elementStack[elementStackTop] == MANIFEST_ITEM) {
			// 			// Add the current manifest item to the list
			// 			manifestItems[manifestItemCount] = currentManifestItem;
			// 			manifestItemCount++;
			// 		} else if (elementStack[elementStackTop] == SPINE_ITEM) {
			// 			// Add the current spine item to the list
			// 			strcpy(spineItems[spineItemCount], currentSpineIdref);
			// 			spineItemCount++;
			// 		}
			// 		const char* elementNameStr = (elementStack[elementStackTop] == MANIFEST) ? "MANIFEST" :
			// 									(elementStack[elementStackTop] == MANIFEST_ITEM) ? "MANIFEST_ITEM" : "UNKNOWN";
			// 		pd->system->logToConsole("Element end: %s", elementNameStr);
			// 	}
			// 	break;
			// case YXML_ATTRSTART:
			// 	pd->system->logToConsole("Attribute start: %s", x.attr);
			// 	break;
			// case YXML_ATTREND:
			// 	pd->system->logToConsole("Attribute end: %s", x.attr);
			// 	// Print the attribute value
			// 	pd->system->logToConsole("Attribute value: %s", currentAttributeValue);
			// 	if (withinManifest(elementStack, elementStackTop)) {
			// 		if (strcmp(x.attr, "id") == 0) {
			// 			strcpy(currentManifestItem.id, currentAttributeValue);
			// 		} else if (strcmp(x.attr, "href") == 0) {
			// 			strcpy(currentManifestItem.href, currentAttributeValue);
			// 		}
			// 	} else if (withinSpine(elementStack, elementStackTop)) {
			// 		if (strcmp(x.attr, "idref") == 0) {
			// 			strcpy(currentSpineIdref, currentAttributeValue);
			// 		}
			// 	}
			// 	// Clear the current attribute value
			// 	free(currentAttributeValue);
			// 	currentAttributeValue = NULL;
			// 	break;
			// case YXML_ATTRVAL:
			// 	// pd->system->logToConsole("Attribute value part: %s", x.data);
			// 	if (currentAttributeValue == NULL) {
			// 		currentAttributeValue = malloc(strlen(x.data) + 1);
			// 		strcpy(currentAttributeValue, x.data);
			// 	} else {
			// 		char *newAttributeValue = realloc(currentAttributeValue, strlen(currentAttributeValue) + strlen(x.data) + 1);
			// 		if (newAttributeValue == NULL) {
			// 			pd->system->logToConsole("Memory allocation failed");
			// 		}
			// 		strcat(newAttributeValue, x.data);
			// 		currentAttributeValue = newAttributeValue;	
			// 	}
			// 	break;
			// case YXML_CONTENT:
			// 	// pd->system->logToConsole("Content: %s", x.data);
			// 	break;
			// default:
			// 	break;
			// }
			parseCode = yxml_parse(&x, 0);
		}
	}
	free(currentAttributeValue);
	debugLog("Done parsing XML file");
	// Print every manifest item
	for (int i = 0; i < manifestItemCount; i++) {
		pd->system->logToConsole("Manifest item %d: id=%s, href=%s", i, manifestItems[i].id, manifestItems[i].href);
	}
	// Print every spine item
	for (int i = 0; i < spineItemCount; i++) {
		pd->system->logToConsole("Spine item %d: idref=%s", i, spineItems[i]);
	}
	// Create an array of content paths in order by linking the manifest items to the spine items
	char **contentPaths = malloc(spineItemCount * sizeof(char *));
	*contentPathCount = 0;
	for (int i = 0; i < spineItemCount; i++) {
		for (int j = 0; j < manifestItemCount; j++) {
			if (strcmp(spineItems[i], manifestItems[j].id) == 0) {
				contentPaths[*contentPathCount] = malloc(strlen(manifestItems[j].href) + 1);
				strcpy(contentPaths[*contentPathCount], manifestItems[j].href);
				(*contentPathCount)++;
				break;
			}
		}
	}

	pd->system->logToConsole("Parsed XML file");
	return contentPaths;
}

static char* htmlToPlaintext(const char *html) {
	int in_tag = 0;
	int index = 0;

	// Allocate memory for the plaintext, give it a little extra since utf-8 characters can be up to 4 bytes long
	char *plaintext = malloc(strlen(html) * 2);
	if (plaintext == NULL) {
		pd->system->logToConsole("Memory allocation failed");
		return NULL; // Memory allocation failed
	}

	for (int i = 0; html[i] != '\0'; i++) {
		if (html[i] == '<') {
			in_tag = 1;
		} else if (html[i] == '>') {
			in_tag = 0;
			// If the tag is a block-level element, add a newline character (as in the previous characters were like </p>, </h1>, etc.)
			if (i > 2 && (html[i - 1] == 'p')) {
				plaintext[index + 1] = '\n';
				plaintext[index + 2] = '\n';
				index += 2;
			}
		} else if (html[i] == '\n') {
			// Ignore newline characters
			continue;
		} else if (html[i] == ' ' && (index == 0 || plaintext[index - 1] == ' ' || plaintext[index - 1] == '\n')) {
			// Combine multiple spaces
			continue;
		} else if (!in_tag) {
			plaintext[index++] = html[i];
		}
	}

	// Null-terminate the plaintext string
	plaintext[index] = '\0';

	return plaintext;
}

static int zippo_readEpub(lua_State* L) {
	debugLog("Reading EPUB");
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
		char *opfContents = NULL;
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
					char *newBuffer = realloc(opfContents, fileSize + rc + 1); // +1 for null terminator
					if (newBuffer == NULL) {
						pd->system->logToConsole("Memory allocation failed\n");
						free(opfContents); // Free the previously allocated memory
						opfContents = NULL;
						break;
					}
					
					opfContents = newBuffer;
					// Copy the read data into the new buffer space
					memcpy(opfContents + fileSize, szTemp, rc);
					fileSize += rc;
					opfContents[fileSize] = '\0'; // Null-terminate the string
				}
			} else {
				pd->system->logToConsole("Error reading from file\n");
				free(opfContents); // Free allocated memory on error
				opfContents = NULL;
				break;
			}
		}

		pd->system->logToConsole("Done reading file");

		if (opfContents != NULL) {
			int contentPathCount = 0;
			char** contentPaths = getContentPaths(opfContents, fileSize, &contentPathCount);
			// Print the content paths
			for (int i = 0; i < contentPathCount; i++) {
				pd->system->logToConsole("Content path %d: %s", i, contentPaths[i]);
			}
			free(opfContents);

			// Read the content of each file
			for (int i = 0; i < contentPathCount; i++) {
				// Create a variable for the path that concats "OEBPS/" and the content path
				char contentPath[256];
				strcpy(contentPath, "OEBPS/");
				strcat(contentPath, contentPaths[i]);
				pd->system->logToConsole("Reading file: %s", contentPath);
				rc = unzLocateFile(zHandle, contentPath, 2);
				if (rc != UNZ_OK) {
					pd->system->logToConsole("File %s not found within archive", contentPath);
					continue;
				}
				rc = unzOpenCurrentFile(zHandle);
				if (rc != UNZ_OK) {
					pd->system->logToConsole("Error opening file %s", contentPath);
					continue;
				}

				char fileBuffer[256];
				int bytesRead;
				char *fileContents = NULL;
				size_t fileSize = 0;
				while ((bytesRead = unzReadCurrentFile(zHandle, fileBuffer, sizeof(fileBuffer))) > 0) {
					char *newBuffer = realloc(fileContents, fileSize + bytesRead + 1);
					if (newBuffer == NULL) {
						pd->system->logToConsole("Memory allocation failed\n");
						free(fileContents);
						fileContents = NULL;
						break;
					}
					fileContents = newBuffer;
					memcpy(fileContents + fileSize, fileBuffer, bytesRead);
					fileSize += bytesRead;
					fileContents[fileSize] = '\0';
				}
				// pd->system->logToConsole("File contents: %s", fileContents);
				char *plaintext = htmlToPlaintext(fileContents);
				// Store plaintext in a file called "plaintext.txt"
				SDFile* file = pd->file->open("plaintext.txt", kFileAppend);
				if (file) {
					pd->system->logToConsole(plaintext);
					pd->file->write(file, plaintext, strlen(plaintext));
					pd->file->close(file);
				} else {
					pd->system->logToConsole("Failed to open file for writing");
				}
				free(fileContents);
				free(plaintext);

				if (bytesRead < 0) {
					pd->system->logToConsole("Error reading file %s", contentPath);
				}

				unzCloseCurrentFile(zHandle);
			}
		}

		// Read through every file

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
	{ "readEpub", zippo_readEpub },
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
