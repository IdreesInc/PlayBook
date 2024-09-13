//
//  array.c
//  Array
//
//  Created by Dave Hayden on 2/24/22.
//  Copyright © 2022 Panic, Inc. All rights reserved.
//

#include "array.h"

static PlaydateAPI* pd = NULL;

typedef struct
{
	int count;
	int* data;
} Array;

static int array_newobject(lua_State* L)
{
	int count = pd->lua->getArgInt(1);
	
	if ( count <= 0 )
		return 0;

	Array* array = pd->system->realloc(NULL, sizeof(Array));
	array->count = count;
	array->data = pd->system->realloc(NULL, sizeof(int) * count);
	pd->lua->pushObject(array, "array", 0);
	return 1;
}

static int array_gc(lua_State* L)
{
	Array* array = pd->lua->getArgObject(1, "array", NULL);
	
	if ( array != NULL )
	{
		pd->system->realloc(array->data, 0);
		pd->system->realloc(array, 0);
	}
	
	return 0;
}

static int array_index(lua_State* L)
{
	// we first need to check if the requested member is defined in the
	// metatable, otherwise we can't call other functions in this class
	
	if ( pd->lua->indexMetatable() )
		return 1;
	
	Array* array = pd->lua->getArgObject(1, "array", NULL);
	int idx = pd->lua->getArgInt(2);
	
	if ( array != NULL && idx > 0 && idx <= array->count )
	{
		pd->lua->pushInt(array->data[idx-1]);
		return 1;
	}
	else
		return 0;
}

static int array_newindex(lua_State* L)
{
	Array* array = pd->lua->getArgObject(1, "array", NULL);
	int idx = pd->lua->getArgInt(2);
	
	if ( pd->lua->getArgType(3, NULL) != kTypeInt )
	{
		pd->system->error("array only accepts integer types");
		return 0;
	}
	
	if ( array != NULL && idx > 0 && idx <= array->count )
		array->data[idx-1] = pd->lua->getArgInt(3);

	return 0;
}

static int array_len(lua_State* L)
{
	Array* array = pd->lua->getArgObject(1, "array", NULL);
	
	if ( array != NULL )
	{
		pd->lua->pushInt(array->count);
		return 1;
	}
	else
		return 0;
}

// while we're here we can add some utility functions..
#include <limits.h>

static int array_getmin(lua_State* L)
{
	Array* array = pd->lua->getArgObject(1, "array", NULL);
	
	if ( array == NULL )
		return 0;

	int min = array->data[0];
	int pos = 0;

	for ( int i = 1; i < array->count; ++i )
	{
		if ( array->data[i] < min )
		{
			min = array->data[i];
			pos = i;
		}
	}
	
	pd->lua->pushInt(min);
	pd->lua->pushInt(pos+1);
	return 2;
}

static int array_getmax(lua_State* L)
{
	Array* array = pd->lua->getArgObject(1, "array", NULL);
	
	if ( array == NULL )
		return 0;
	
	int max = array->data[0];
	int pos = 0;

	for ( int i = 1; i < array->count; ++i )
	{
		if ( array->data[i] > max )
		{
			max = array->data[i];
			pos = i;
		}
	}
	
	pd->lua->pushInt(max);
	pd->lua->pushInt(pos+1);
	return 2;
}

static int array_getavg(lua_State* L)
{
	Array* array = pd->lua->getArgObject(1, "array", NULL);
	long long sum = 0;
	
	for ( int i = 0; i < array->count; ++i )
		sum += array->data[i];
	
	pd->lua->pushInt(sum/array->count);
	return 1;
}


static const lua_reg arrayLib[] =
{
	{ "new", 		array_newobject },
	{ "__gc",		array_gc },
	{ "__index", 	array_index },
	{ "__newindex",	array_newindex },
	{ "__len",		array_len },
	{ "getMinimum", array_getmin },
	{ "getMaximum", array_getmax },
	{ "getAverage", array_getavg },
	{ NULL, NULL }
};

void registerArray(PlaydateAPI* playdate)
{
	pd = playdate;
	
	const char* err;
	
	if ( !pd->lua->registerClass("array", arrayLib, NULL, 0, &err) )
		pd->system->logToConsole("%s:%i: registerClass failed, %s", __FILE__, __LINE__, err);
}
