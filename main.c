//
//  main.c
//  Extension
//
//  Created by Dan Messing on 5/01/18.
//  Copyright (c) 2018 Panic, Inc. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "pd_api.h"
#include "array.h"

static PlaydateAPI* pd = NULL;

#ifdef _WINDLL
__declspec(dllexport)
#endif
int eventHandler(PlaydateAPI* playdate, PDSystemEvent event, uint32_t arg)
{
	(void)arg;

	if ( event == kEventInitLua )
	{
		pd = playdate;
		registerArray(pd);
	}

	return 0;
}
