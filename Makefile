HEAP_SIZE      = 8388208
STACK_SIZE     = 61800

PRODUCT = PlayBook.pdx

# Locate the SDK
SDK = ${PLAYDATE_SDK_PATH}
ifeq ($(SDK),)
SDK = $(shell egrep '^\s*SDKRoot' ~/.Playdate/config | head -n 1 | cut -c9-)
endif

ifeq ($(SDK),)
$(error SDK path not found; set ENV value PLAYDATE_SDK_PATH)
endif

UNZIP_DIR = ./unzip

# List C source files here
SRC = main.c array.c zippo.c yxml.c $(wildcard $(UNZIP_DIR)/*.c)

# List all user directories here
UINCDIR = 

# List user asm files
UASRC = 

# List all user C define here, like -D_DEBUG=1
UDEFS = 

# Define ASM defines here
UADEFS = 

# List the user directory to look for the libraries here
ULIBDIR =

# List all user libraries here
ULIBS =

# Enable AddressSanitizer
CFLAGS += -fsanitize=address -g -O1
LDFLAGS += -fsanitize=address

include $(SDK)/C_API/buildsupport/common.mk
