#!/usr/bin/env zsh

# File: ztui_framework.zsh
# Overview: Main entry point for the Zsh TUI Framework.
# Implements a main bordered layout with menu and title in the top border.

if [ -z "$ZSH_VERSION" ]; then
  printf "Error: This script requires Zsh to run.\n" >&2
  exit 1
fi

ZTUI_LIB_DIR="${0:A:h}/ztui_lib"
ZTUI_LOG_DIR="${0:A:h}/logs" 

# Function to source library files
source_lib() {
  local lib_name="$1"
  local lib_path="$ZTUI_LIB_DIR/$lib_name.zsh"
  if [[ -f "$lib_path" ]]; then
    source "$lib_path"
    if [[ $? -ne 0 ]]; then
      if typeset -f ztui_log >/dev/null; then 
        ztui_log "FATAL" "Failed to source or initialize from '$lib_path'. Exiting."
      else
        print -u2 "FATAL Error (ztui_framework.zsh): Failed to source or initialize from '$lib_path'. Exiting."
      fi
      if typeset -f ztui_end_screen >/dev/null; then ztui_end_screen; fi
      exit 1
    fi
  else
    if typeset -f ztui_log >/dev/null; then 
      ztui_log "FATAL" "Library '$lib_path' not found. Exiting."
    else
      print -u2 "FATAL Error (ztui_framework.zsh): Library '$lib_path' not found. Exiting."
    fi
    exit 1
  fi
}

# Source libraries in order of dependency
source_lib "core_logger"    
source_lib "core_drawing"   
source_lib "core_screen"    
source_lib "core_input"     
source_lib "widget_menubar" 

################################################################################
# Command-line Option Parsing
################################################################################
# Corrected variable names for zparseopts
local arg_logfile_path=""
local arg_loglevel_value=""
local arg_show_help=""

zparseopts -D -E -- \
  {l,-logfile}=arg_logfile_path \
  {L,-loglevel}=arg_loglevel_value \
  {h,-help}=arg_show_help

if [[ -n "$arg_show_help" ]]; then # Use the correct variable
  print "Zsh TUI Framework"
  print "Usage: $0 [options]"
  print "Options:"
  print "  -l, --logfile FILE_PATH   Path to the log file. Logging is disabled if not provided."
  print "                            Default log directory is './logs/' relative to script."
  print "  -L, --loglevel LEVEL      Set log level (DEBUG, INFO, WARN, ERROR). Default: INFO."
  print "  -h, --help                Show this help message."
  exit 0
fi

if [[ -n "$arg_logfile_path" ]]; then # Use the correct variable
  local logfile_target="$arg_logfile_path[2]" # Value is in the second element for options with arguments
  if [[ -z "$logfile_target" && -n "$arg_logfile_path[1]" ]]; then # Fallback if -lValue format used
      logfile_target="$arg_logfile_path[1]" 
      # This case might need more robust handling if -lValue is common
  fi

  if [[ -n "$logfile_target" ]]; then
    if [[ "$logfile_target" != /* && "$logfile_target" != */* ]]; then # Simple filename, no path
        mkdir -p "$ZTUI_LOG_DIR" 2>/dev/null 
        if [[ -d "$ZTUI_LOG_DIR" ]]; then
            logfile_target="$ZTUI_LOG_DIR/$logfile_target"
        else
            print -u2 "Warning: Could not create/access log directory '$ZTUI_LOG_DIR'. Using path '$logfile_target' as is."
        fi
    elif [[ "$logfile_target" != /* ]]; then # Relative path with directory components
        print -u2 "Info: Using relative logfile path: '$logfile_target'"
    fi
    ztui_set_logfile "$logfile_target" 
  else
    print -u2 "Warning: --logfile option used but no filename was captured."
  fi
fi

if [[ -n "$arg_loglevel_value" ]]; then # Use the correct variable
    local loglevel_target="$arg_loglevel_value[2]" # Value is in the second element
    if [[ -z "$loglevel_target" && -n "$arg_loglevel_value[1]" ]]; then # Fallback
        loglevel_target="$arg_loglevel_value[1]"
    fi
    if [[ -n "$loglevel_target" ]]; then
        ztui_set_loglevel "$loglevel_target"
    else
        print -u2 "Warning: --loglevel option used but no level value was captured."
    fi
fi

ztui_log "INFO" "Application starting with Zsh version: $ZSH_VERSION"
################################################################################
# Main Application Logic
################################################################################

TRAPEXIT() {
  ztui_log "INFO" "Application exiting via TRAPEXIT."
  if typeset -f ztui_end_screen >/dev/null; then
    ztui_end_screen
  fi
  ztui_log "INFO" "Application finished."
}

typeset -A top_menu_items
top_menu_items=(
  "File" "New Open Save --- Quit" 
  "Edit" "Cut Copy Paste Find"
  "View" "Statusbar Toolbar Zoom"
  "Help" "About Index Manual"
)
ztui_init_menubar_order top_menu_items # From widget_menubar.zsh

typeset -g ZTUI_MAIN_TITLE="Zsh TUI Framework v0.3"

main() {
  ztui_init_screen # From core_screen.zsh
  if [[ $? -ne 0 ]]; then
    ztui_log "FATAL" "ztui_init_screen failed. Exiting."
    exit 1
  fi

  ztui_log "INFO" "Main loop started."
  while true; do
    # Draw the top border which includes menu and title (from core_screen.zsh)
    ztui_draw_top_border_with_menu_title "$ZTUI_MAIN_TITLE" 
    
    if (( ZTUI_SUBMENU_ACTIVE == 1 )); then
        ztui_draw_submenu # From widget_menubar.zsh
    fi
    
    ztui_refresh_screen # From core_screen.zsh

    local logical_key
    logical_key=$(ztui_get_key) # From core_input.zsh

    ztui_log "DEBUG" "Key received: '$logical_key' (Raw Char: '$ZTUI_INPUT_CHAR', Special: '$ZTUI_INPUT_SPECIAL')"

    if [[ "$logical_key" == "q" && $ZTUI_SUBMENU_ACTIVE -eq 0 ]]; then 
      ztui_log "INFO" "'q' pressed in main context, exiting main loop."
      break
    fi

    if (( ZTUI_SUBMENU_ACTIVE == 1 )); then
      case "$logical_key" in
        "KEY_ESC")
          ztui_close_submenu # From widget_menubar.zsh
          ;;
        "KEY_UP")
          ztui_log "DEBUG" "Submenu: UP pressed (navigation not implemented)"
          ;;
        "KEY_DOWN")
          ztui_log "DEBUG" "Submenu: DOWN pressed (navigation not implemented)"
          ;;
        "KEY_ENTER")
          local selected_submenu_item="${ZTUI_SUBMENU_ITEMS[$((ZTUI_SUBMENU_ACTIVE_ITEM_INDEX + 1))]}" 
          ztui_log "INFO" "Submenu item selected: '$selected_submenu_item'"
          if [[ "$selected_submenu_item" == "Quit" ]]; then
              ztui_log "INFO" "'Quit' selected from submenu. Exiting application."
              ztui_close_submenu 
              return 0 
          fi
          ztui_close_submenu 
          ;;
        *)
          ztui_log "DEBUG" "Key '$logical_key' ignored in submenu context."
          ;;
      esac
    else # Main screen / menubar input
      case "$logical_key" in
        "KEY_LEFT")
          ztui_navigate_menubar "LEFT" # From widget_menubar.zsh
          ;;
        "KEY_RIGHT")
          ztui_navigate_menubar "RIGHT" # From widget_menubar.zsh
          ;;
        "KEY_ENTER"|"KEY_DOWN") 
          ztui_open_submenu top_menu_items # From widget_menubar.zsh
          ;;
        "KEY_ESC")
          ztui_log "DEBUG" "ESC pressed on main screen (no action defined)."
          ;;
        *)
          ztui_log "DEBUG" "Key '$logical_key' ignored in main context."
          ;;
      esac
    fi
  done
  ztui_log "INFO" "Main loop finished."
}

main
exit 0 
