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

static void listFilesCallback(const char *name, void *userdata) {
    pd->system->logToConsole("File: %s", name);
}

void *myOpen(const char *filename, int32_t *size)
{
    pd->system->logToConsole("Attempting to open file: %s", filename);
    size_t filesize;
    SDFile *myfile = pd->file->open(filename, kFileReadData);
    if (myfile)
    {
        pd->file->seek(myfile, 0, SEEK_END);
        filesize = pd->file->tell(myfile);
        pd->file->seek(myfile, 0, SEEK_SET);
        *size = (int32_t)filesize;
    } else {
		pd->system->logToConsole("Failed to open file: %s", filename);
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

int32_t listFiles(void) {
	pd->system->logToConsole("Listing files...");
	pd->file->listfiles(".", listFilesCallback, 0, 0);
	return 0;
}

static void debugLog(const char *message) {
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

// Make an enum of relevant element names including MANIFEST and MANIFEST_ITEM
typedef enum
{
	UNKNOWN,
	MANIFEST,
	MANIFEST_ITEM,
	SPINE,
	SPINE_ITEM,
	NAVPOINT,
	NAVLABEL,
	NAVTEXT,
	NAVCONTENT
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

static char* getRootfile(char *containerContents, size_t fileSize) {
	// Parse the XML file
	yxml_t x;
	yxml_init(&x, containerContents, fileSize);
	
	ElementName elementStack[1000] = {UNKNOWN};
	int elementStackTop = 0;

	// Store the rootfile path
	char *rootfilePath = NULL;
	// Store the current attribute value
	char *currentAttributeValue = NULL;
	bool inRootfileElement = false;
	debugLog("Starting parse of XML file");
	int count = 0;
	for (int i = 0; i < fileSize; i++) {
		int parseCode = yxml_parse(&x, containerContents[i]);
		while (parseCode > 0 && rootfilePath == NULL) {
			switch (parseCode) {
			case YXML_ELEMSTART:
				if (strcmp(x.elem, "rootfile") == 0) {
					inRootfileElement = true;
				}
				break;
			case YXML_ELEMEND:
				if (inRootfileElement) {
					inRootfileElement = false;
				}
				break;
			case YXML_ATTREND:
				if (inRootfileElement &&  strcmp(x.attr, "full-path") == 0) {
					rootfilePath = malloc(strlen(currentAttributeValue) + 1);
					strcpy(rootfilePath, currentAttributeValue);
				}
				currentAttributeValue = NULL;
				break;
			case YXML_ATTRVAL:
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
			default:
				break;
			}
			parseCode = yxml_parse(&x, 0);
		}
	}
	free(currentAttributeValue);
	debugLog("Done parsing XML file");
	return rootfilePath;
}

typedef struct {
	/** The paths to each of the ebook's contents in order */	
	char **contentPaths;
	/** The path to the table of contents .ncx file */
	char *tocPath;
} ContentPaths;

static ContentPaths getContentPaths(char *opfContents, size_t fileSize, int *contentPathCount) {
	// Parse the XML file
	yxml_t x;
	yxml_init(&x, opfContents, fileSize);
	
	ElementName elementStack[1000] = {UNKNOWN};
	int elementStackTop = 0;

	// Store manifest items in a dynamically allocated array
    char *manifestIds[100];
	char *manifestHrefs[100];
	int manifestItemCount = 0;
	char currentManifestId[256];
	char currentManifestHref[256];
	// Store spine items as an array of dynamically allocated strings
	char *spineItems[100];
	int spineItemCount = 0;
	char currentSpineIdref[256];
	// Store the current attribute value
	char *currentAttributeValue = NULL;
	char *tableOfContentsId = NULL;
	char *tableOfContentsPath = NULL;
	debugLog("Starting parse of XML file");
	int count = 0;
	for (int i = 0; i < fileSize; i++) {
		int parseCode = yxml_parse(&x, opfContents[i]);
		while (parseCode > 0) {
			// pd->system->logToConsole("Parse code: %d", parseCode);
			switch (parseCode) {
			case YXML_ELEMSTART:
				// pd->system->logToConsole("Element start: %s", x.elem);
				if (strcmp(x.elem, "manifest") == 0) {
					elementStack[elementStackTop] = MANIFEST;
				} else if (strcmp(x.elem, "item") == 0 && withinManifest(elementStack, elementStackTop)) {
					elementStack[elementStackTop] = MANIFEST_ITEM;
				} else if (strcmp(x.elem, "spine") == 0) {
					elementStack[elementStackTop] = SPINE;
				} else if (strcmp(x.elem, "itemref") == 0 && withinSpine(elementStack, elementStackTop)) {
					elementStack[elementStackTop] = SPINE_ITEM;
				} else {
					elementStack[elementStackTop] = UNKNOWN;
				}
				elementStackTop++;
				break;
			case YXML_ELEMEND:
				// Cannot use x.elem to determine closing element: https://code.blicky.net/yorhel/yxml/issues/7
				if (elementStackTop == 0) {
					pd->system->logToConsole("ERROR: Element stack is empty and yet pop was attempted");
				} else {
					elementStackTop--;
					if (elementStack[elementStackTop] == MANIFEST_ITEM) {
						// Add the current manifest item to the list
						manifestIds[manifestItemCount] = malloc(strlen(currentManifestId) + 1);
						strcpy(manifestIds[manifestItemCount], currentManifestId);
						manifestHrefs[manifestItemCount] = malloc(strlen(currentManifestHref) + 1);
						strcpy(manifestHrefs[manifestItemCount], currentManifestHref);
						manifestItemCount++;
						// pd->system->logToConsole("Manifest item: id=%s, href=%s", currentManifestId, currentManifestHref);
					} else if (elementStack[elementStackTop] == SPINE_ITEM) {
						// Add the current spine item to the list
						spineItems[spineItemCount] = malloc(strlen(currentSpineIdref) + 1);
						strcpy(spineItems[spineItemCount], currentSpineIdref);
						spineItemCount++;
						// pd->system->logToConsole("Spine item: idref=%s", currentSpineIdref);
					}
					const char* elementNameStr = (elementStack[elementStackTop] == MANIFEST) ? "MANIFEST" :
												(elementStack[elementStackTop] == MANIFEST_ITEM) ? "MANIFEST_ITEM" : "UNKNOWN";
					// pd->system->logToConsole("Element end: %s", elementNameStr);
				}
				break;
			case YXML_ATTRSTART:
				// pd->system->logToConsole("Attribute start: %s", x.attr);
				break;
			case YXML_ATTREND:
				// pd->system->logToConsole("Attribute end: %s", x.attr);
				// Print the attribute value
				// pd->system->logToConsole("Attribute value: %s", currentAttributeValue);
				if (withinManifest(elementStack, elementStackTop)) {
					if (strcmp(x.attr, "id") == 0) {
						strcpy(currentManifestId, currentAttributeValue);
					} else if (strcmp(x.attr, "href") == 0) {
						strcpy(currentManifestHref, currentAttributeValue);
					}
				} else if (withinSpine(elementStack, elementStackTop)) {
					if (strcmp(x.attr, "idref") == 0) {
						strcpy(currentSpineIdref, currentAttributeValue);
					}
				}
				if (strcmp(x.elem, "spine") == 0 && strcmp(x.attr, "toc") == 0) {
					tableOfContentsId = malloc(strlen(currentAttributeValue) + 1);
					strcpy(tableOfContentsId, currentAttributeValue);
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
			parseCode = yxml_parse(&x, 0);
		}
	}
	free(currentAttributeValue);
	debugLog("Done parsing XML file");
	// // Print every manifest item
	// for (int i = 0; i < manifestItemCount; i++) {
	// 	pd->system->logToConsole("Manifest item %d: id=%s, href=%s", i, manifestIds[i], manifestHrefs[i]);
	// }
	// // Print every spine item
	// for (int i = 0; i < spineItemCount; i++) {
	// 	pd->system->logToConsole("Spine item %d: idref=%s", i, spineItems[i]);
	// }
	// Create an array of content paths in order by linking the manifest items to the spine items
	char **contentPaths = malloc(spineItemCount * sizeof(char *));
	*contentPathCount = 0;
	for (int i = 0; i < spineItemCount; i++) {
		for (int j = 0; j < manifestItemCount; j++) {
			if (strcmp(spineItems[i], manifestIds[j]) == 0) {
				contentPaths[*contentPathCount] = malloc(strlen(manifestHrefs[j]) + 1);
				strcpy(contentPaths[*contentPathCount], manifestHrefs[j]);
				(*contentPathCount)++;
				break;
			}
		}
	}
	// Determine the path to the table of contents file
	for (int i = 0; i < manifestItemCount; i++) {
		if (strcmp(manifestIds[i], tableOfContentsId) == 0) {
			tableOfContentsPath = malloc(strlen(manifestHrefs[i]) + 1);
			strcpy(tableOfContentsPath, manifestHrefs[i]);
			break;
		}
	}
	pd->system->logToConsole("Parsed XML file");
	ContentPaths paths;
	paths.contentPaths = contentPaths;
	paths.tocPath = tableOfContentsPath;
	return paths;
}

typedef struct {
	char *name;
	char *path;
} TableOfContentsItem;

static bool withinNavPoint(ElementName* stack, int top) {
	return stack[top - 1] == NAVPOINT;
}

static bool withinNavLabel(ElementName* stack, int top) {
	return stackContains(stack, top, NAVLABEL);
}

static bool withinNavText(ElementName* stack, int top) {
	return stackContains(stack, top, NAVTEXT);
}

static bool withinNavContent(ElementName* stack, int top) {
	return stackContains(stack, top, NAVCONTENT);
}

static TableOfContentsItem* parseTableOfContents(char *tocContents, size_t fileSize, int *tocItemCount) {
	// Parse the XML file
	yxml_t x;
	yxml_init(&x, tocContents, fileSize);
	ElementName elementStack[1000] = {UNKNOWN};
	int elementStackTop = 0;

	TableOfContentsItem *tocItems = malloc(300 * sizeof(TableOfContentsItem));
	*tocItemCount = 0;

	char *currentAttributeValue = NULL;
	char *currentNavLabelText = NULL;
	char *currentNavPointPath = NULL;

	debugLog("Starting parse of XML file");

	for (int i = 0; i < fileSize; i++) {
		int parseCode = yxml_parse(&x, tocContents[i]);
		while (parseCode > 0) {
			switch (parseCode) {
				case YXML_ELEMSTART:
					if (strcmp(x.elem, "navPoint") == 0 && !withinNavPoint(elementStack, elementStackTop)) {
						// Don't allow nested navPoints for now
						elementStack[elementStackTop] = NAVPOINT;
					} else if (strcmp(x.elem, "navLabel") == 0 && withinNavPoint(elementStack, elementStackTop)) {
						elementStack[elementStackTop] = NAVLABEL;
					} else if (strcmp(x.elem, "text") == 0 && withinNavLabel(elementStack, elementStackTop)) {
						elementStack[elementStackTop] = NAVTEXT;
					} else if (strcmp(x.elem, "content") == 0 && withinNavPoint(elementStack, elementStackTop)) {
						elementStack[elementStackTop] = NAVCONTENT;
					} else {
						elementStack[elementStackTop] = UNKNOWN;
					}
					elementStackTop++;
					break;
				case YXML_ELEMEND:
					if (elementStackTop == 0) {
						pd->system->logToConsole("ERROR: Element stack is empty and yet pop was attempted");
					} else {
						elementStackTop--;
						if (elementStack[elementStackTop] == NAVPOINT) {
							tocItems[*tocItemCount].name = currentNavLabelText;
							tocItems[*tocItemCount].path = currentNavPointPath;
							(*tocItemCount)++;
							currentNavLabelText = NULL;
							currentNavPointPath = NULL;
						}
					}
					break;
				case YXML_ATTREND:
					if (withinNavContent(elementStack, elementStackTop) && strcmp(x.attr, "src") == 0) {
						currentNavPointPath = malloc(strlen(currentAttributeValue) + 1);
						strcpy(currentNavPointPath, currentAttributeValue);
					}
					free(currentAttributeValue);
					currentAttributeValue = NULL;
					break;
				case YXML_ATTRVAL:
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
					if (withinNavText(elementStack, elementStackTop)) {
						if (currentNavLabelText == NULL) {
							currentNavLabelText = malloc(strlen(x.data) + 1);
							strcpy(currentNavLabelText, x.data);
						} else {
							char *newNavLabelText = realloc(currentNavLabelText, strlen(currentNavLabelText) + strlen(x.data) + 1);
							if (newNavLabelText == NULL) {
								pd->system->logToConsole("Memory allocation failed");
							}
							strcat(newNavLabelText, x.data);
							currentNavLabelText = newNavLabelText;
						}
					}
					break;
				default:
					break;
			}
			parseCode = yxml_parse(&x, 0);
		}
	}
	free(currentAttributeValue);
	debugLog("Done parsing XML file");
	return tocItems;
}

// Constant containing html entities and their corresponding characters
static const char *htmlEntities[] = {
	"&amp;", "&",
	"&lt;", "<",
	"&gt;", ">",
	"&quot;", "\"",
	"&apos;", "'",
	"&nbsp;", " ",
	"&iexcl;", "¡",
	"&cent;", "¢",
	"&pound;", "£",
	"&curren;", "¤",
	"&yen;", "¥",
	"&brvbar;", "¦",
	"&sect;", "§",
	"&uml;", "¨",
	"&copy;", "©",
	"&ordf;", "ª",
	"&laquo;", "«",
	"&not;", "¬",
	"&shy;", "­",
	"&reg;", "®",
	"&macr;", "¯",
	"&deg;", "°",
	"&plusmn;", "±",
	"&sup2;", "²",
	"&sup3;", "³",
	"&acute;", "´",
	"&micro;", "µ",
	"&para;", "¶",
	"&middot;", "·",
	"&cedil;", "¸",
	"&sup1;", "¹",
	"&ordm;", "º",
	"&raquo;", "»",
	"&frac14;", "¼",
	"&frac12;", "½",
	"&frac34;", "¾",
	"&iquest;", "¿",
	"&Agrave;", "À",
	"&Aacute;", "Á",
	"&Acirc;", "Â",
	"&Atilde;", "Ã",
	"&Auml;", "Ä",
	"&Aring;", "Å",
	"&AElig;", "Æ",
	"&Ccedil;", "Ç",
	"&Egrave;", "È",
	"&Eacute;", "É",
	"&Ecirc;", "Ê",
	"&Euml;", "Ë",
	"&Igrave;", "Ì",
	"&Iacute;", "Í",
	"&Icirc;", "Î",
	"&Iuml;", "Ï",
	"&ETH;", "Ð",
	"&Ntilde;", "Ñ",
	"&Ograve;", "Ò",
	"&Oacute;", "Ó",
	"&Ocirc;", "Ô",
	"&Otilde;", "Õ",
	"&Ouml;", "Ö",
	"&times;", "×",
	"&Oslash;", "Ø",
	"&Ugrave;", "Ù",
	"&Uacute;", "Ú",
	"&Ucirc;", "Û",
	"&Uuml;", "Ü",
	"&Yacute;", "Ý",
	"&THORN;", "Þ",
	"&szlig;", "ß",
	"&agrave;", "à",
	"&aacute;", "á",
	"&acirc;", "â",
	"&atilde;", "ã",
	"&auml;", "ä",
	"&aring;", "å",
	"&aelig;", "æ",
	"&ccedil;", "ç",
	"&egrave;", "è",
	"&eacute;", "é",
	"&ecirc;", "ê",
	"&euml;", "ë",
	"&igrave;", "ì",
	"&iacute;", "í",
	"&icirc;", "î",
	"&iuml;", "ï",
	"&eth;", "ð",
	"&ntilde;", "ñ",
	"&ograve;", "ò",
	"&oacute;", "ó",
	"&ocirc;", "ô",
	"&otilde;", "õ",
	"&ouml;", "ö",
	"&divide;", "÷",
	"&oslash;", "ø",
	"&ugrave;", "ù",
	"&uacute;", "ú",
	"&ucirc;", "û",
	"&uuml;", "ü",
	"&yacute;", "ý",
	"&thorn;", "þ",
	"&yuml;", "ÿ",
	NULL, NULL
};

static char* htmlToPlaintext(const char *html, size_t fileSize) {
	bool withinTag = false;
	int index = 0;

	// Allocate memory for the plaintext, give it a little extra since utf-8 characters can be up to 4 bytes long
	char *plaintext = malloc(strlen(html) * 2);
	if (plaintext == NULL) {
		pd->system->logToConsole("Memory allocation failed");
		return NULL; // Memory allocation failed
	}

	for (int i = 0; i < fileSize; i++) {
		if (html[i] == '<') {
			withinTag = true;
			if (i + 3 < fileSize && html[i + 1] == '/') {
				// Add an extra newline after headings
				if (html[i + 2] == 'h') {
					plaintext[index++] = ' ';
					plaintext[index++] = '\n';
				}
			} else if (i + 3 < fileSize && (html[i + 1] == 'p' || html[i + 1] == 'h')) {
				// Add a couple of newlines before block elements
				plaintext[index++] = ' ';
				plaintext[index++] = '\n';
				plaintext[index++] = ' ';
				plaintext[index++] = '\n';
			}
		} else if (html[i] == '>') {
			withinTag = false;
		} else if (html[i] == '\n' && ((index == 0 || plaintext[index - 1] != '\n') || (index >= fileSize - 1 || html[i + 1] != '\n'))) {
			// Skip newlines that are not adjacent to other newlines
			continue;
		} else if (html[i] == ' ' && (index == 0 || plaintext[index - 1] == ' ' || plaintext[index - 1] == '\n')) {
			// Combine multiple spaces
			continue;
		} else if (!withinTag) {
			if (html[i] == '&') {
				// Determine if the character is an HTML entity
				bool isEntity = false;
				for (int j = 0; htmlEntities[j] != NULL; j += 2) {
					if (strncmp(html + i, htmlEntities[j], strlen(htmlEntities[j])) == 0) {
						plaintext[index++] = htmlEntities[j + 1][0];
						i += strlen(htmlEntities[j]) - 1;
						isEntity = true;
						break;
					}
				}
				if (isEntity) {
					continue;
				}
			}
			plaintext[index++] = html[i];
		}
	}

	// Null-terminate the plaintext string
	plaintext[index] = '\0';

	// // pd->system->logToConsole(plaintext);
	// // Split and log each line to the console
	// // When uncommented, will delete original plaintext
	// char *line = strtok(plaintext, "\n");
	// while (line != NULL) {
	// 	// pd->system->logToConsole(line);
	// 	line = strtok(NULL, "\n");
	// }
	// return "debuggo";

	return plaintext;
}

static char* readFileFromZip(unzFile zHandle, const char* filePath) {
	int rc = unzLocateFile(zHandle, filePath, 2);
	if (rc != UNZ_OK) {
		pd->system->logToConsole("File %s not found within archive", filePath);
		return NULL;
	}
	rc = unzOpenCurrentFile(zHandle);
	if (rc != UNZ_OK) {
		pd->system->logToConsole("Error opening file %s", filePath);
		return NULL;
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
			return NULL;
		}
		fileContents = newBuffer;
		memcpy(fileContents + fileSize, fileBuffer, bytesRead);
		fileSize += bytesRead;
		fileContents[fileSize] = '\0';
	}

	if (bytesRead < 0) {
		pd->system->logToConsole("Error reading file %s", filePath);
		free(fileContents);
		return NULL;
	}

	unzCloseCurrentFile(zHandle);
	return fileContents;
}

static int zippo_expandEpub(lua_State* L) {
	debugLog("Reading EPUB");
	const char *zipfilename = pd->lua->getArgString(1);
	const char *outputFilename = pd->lua->getArgString(2);

	listFiles();
	pd->system->logToConsole("Unzipping %s", zipfilename);
	int rc = 0;
	ZIPFILE zpf;
	unzFile zHandle = unzOpen(zipfilename, NULL, 0, &zpf, myOpen, myRead, mySeek, myClose);

	if (zHandle == NULL) {
		pd->system->logToConsole("Failed to unzip %s", zipfilename);
		return 0;
	}

	char szComment[256];
	rc = unzGetGlobalComment(zHandle, szComment, sizeof(szComment));
	if (rc != UNZ_OK) {
		pd->system->logToConsole("Bad comment while unzipping: %d", rc);
		return 0;
	}

	pd->system->logToConsole("Ebook unzipped successfully");

	// Open the META-INF/container.xml file to read the path to the opf file
	pd->system->logToConsole("Opening container.xml...");
	char *containerPath = "META-INF/container.xml";
	char *containerContents = readFileFromZip(zHandle, containerPath);
	if (containerContents == NULL) {
		pd->system->logToConsole("Could not locate container.xml within META-INF, invalid EPUB");
		unzClose(zHandle);
		return 0;
	}
	// Get the rootfile path
	char *rootfilePath = getRootfile(containerContents, strlen(containerContents));
	if (rootfilePath == NULL) {
		pd->system->logToConsole("Could not locate rootfile within container.xml, invalid EPUB");
		unzClose(zHandle);
		return 0;
	}
	pd->system->logToConsole("Rootfile path: %s", rootfilePath);
	free(containerContents);

	// Open the opf file to read the manifest
	pd->system->logToConsole("Opening rootfile at %s...", rootfilePath);
	char *opfPath = rootfilePath;
	char *opfContents = readFileFromZip(zHandle, opfPath);
	if (opfContents == NULL) {
		pd->system->logToConsole("File %s not found within archive", opfPath);
		unzClose(zHandle);
		return 0;
	}

	int contentPathCount = 0;
	ContentPaths paths = getContentPaths(opfContents, strlen(opfContents), &contentPathCount);
	char** contentPaths = paths.contentPaths;
	char* tocPath = paths.tocPath;
	free(opfContents);

	// Get the prefix of the opf file path to use for reading the content files
	char *opfPrefix = malloc(strlen(opfPath) + 1);
	strcpy(opfPrefix, opfPath);
	char *lastSlash = strrchr(opfPrefix, '/');
	if (lastSlash != NULL) {
		*lastSlash = '\0';
	} else {
		strcpy(opfPrefix, "");
	}
	// Add a slash to the prefix if it is not empty
	if (strlen(opfPrefix) > 0) {
		strcat(opfPrefix, "/");
	}
	pd->system->logToConsole("OPF prefix: %s", opfPrefix);

	// Process table of contents (if provided by opf file)
	// Only used for structure and navigation, not for content extraction
	if (tocPath != NULL) {
		// Prepend the prefix to the table of contents path
		char tocFullPath[256];
		strcpy(tocFullPath, opfPrefix);
		strcat(tocFullPath, tocPath);
		pd->system->logToConsole("Opening table of contents at %s...", tocFullPath);
		char *tocContents = readFileFromZip(zHandle, tocFullPath);
		if (tocContents == NULL) {
			pd->system->logToConsole("File %s not found within archive", tocFullPath);
		} else {
			// File size print
			int tocItemCount = 0;
			TableOfContentsItem* tocItems = parseTableOfContents(tocContents, strlen(tocContents), &tocItemCount);
			free(tocContents);

			// Print the table of contents items
			for (int i = 0; i < tocItemCount; i++) {
				pd->system->logToConsole("TOC item %d: name=%s, path=%s", i, tocItems[i].name, tocItems[i].path);
			}

			// Free the table of contents items
			for (int i = 0; i < tocItemCount; i++) {
				free(tocItems[i].name);
				free(tocItems[i].path);
			}
			free(tocItems);
		}
	}

	// Print the content paths
	for (int i = 0; i < contentPathCount; i++) {
		pd->system->logToConsole("Content path %d: %s", i, contentPaths[i]);
	}

	// Store plaintext in a file called "plaintext.txt"
	pd->file->unlink(outputFilename, 0);
	pd->system->logToConsole("Opening file for writing: %s", outputFilename);
	SDFile* file = pd->file->open(outputFilename, kFileAppend);

	// Read the content of each file
	for (int i = 1; i < contentPathCount; i++) {
		// Create a variable for the path that concats "OEBPS/" and the content path
		char contentPath[256];
		strcpy(contentPath, opfPrefix);
		strcat(contentPath, contentPaths[i]);
		pd->system->logToConsole("Reading file: %s", contentPath);
		char *fileContents = readFileFromZip(zHandle, contentPath);
		if (fileContents == NULL) {
			continue;
		}

		char *plaintext = htmlToPlaintext(fileContents, strlen(fileContents));
		if (file) {
			pd->system->logToConsole("Writing to file with length %d", strlen(plaintext));
			pd->file->write(file, plaintext, strlen(plaintext));
		} else {
			pd->system->logToConsole("Failed to open file for writing");
		}
		free(fileContents);
		free(plaintext);
	}

	pd->file->close(file);
	unzClose(zHandle);
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
	{ "expandEpub", zippo_expandEpub },
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
