# File: widget_menubar.zsh
# Overview: Handles menu bar state (active item, submenu data) and navigation logic.
# The actual drawing of the inline menu is now done by core_screen.zsh/ztui_draw_top_border_with_menu_title.

################################################################################
# Guard against direct execution
################################################################################
if [[ "$0" == "$ZSH_SCRIPT" ]]; then
    print -u2 "Error: This script ($0) is a library and should be sourced, not executed directly."
    exit 1
fi

################################################################################
# Menu Bar State and Configuration
################################################################################

typeset -g ZTUI_MENUBAR_ACTIVE_INDEX=0
typeset -ag ZTUI_MENUBAR_ITEM_ORDER # Holds the order of top-level menu keys
typeset -g ZTUI_SUBMENU_ACTIVE=0 
typeset -g ZTUI_SUBMENU_PARENT_ITEM_X_ON_SCREEN=0 # Screen X coord for submenu alignment, set by drawing func
typeset -ag ZTUI_SUBMENU_ITEMS
typeset -g ZTUI_SUBMENU_ACTIVE_ITEM_INDEX=0 

# Define default and highlight attributes (used by core_screen.zsh for drawing)
typeset -g ZTUI_ATTR_MENUBAR_NORMAL="default/default"
typeset -g ZTUI_ATTR_MENUBAR_ACTIVE="white/blue" 

# ZTUI_MENU_BORDER_SEPARATOR is defined in core_drawing.zsh

# Initialize menu bar item order from the associative array keys
ztui_init_menubar_order() {
    local MENU_ITEMS_ASSOC_NAME="$1"
    # Using (kP) to get keys in defined order (for recent Zsh versions)
    ZTUI_MENUBAR_ITEM_ORDER=("${(kP)MENU_ITEMS_ASSOC_NAME}")
    ztui_log "DEBUG" "Menubar item order initialized. Items: ${ZTUI_MENUBAR_ITEM_ORDER[*]}"
}

# The function ztui_draw_menubar_inline was moved into core_screen.zsh's 
# ztui_draw_top_border_with_menu_title for simpler coordinate management.

# Navigation logic for the top-level menu bar
ztui_navigate_menubar() {
  local DIRECTION="$1"
  local num_items=${#ZTUI_MENUBAR_ITEM_ORDER[@]}

  if (( num_items == 0 )); then 
    ztui_log "WARN" "ztui_navigate_menubar: No menu items to navigate."
    return
  fi

  if [[ "$DIRECTION" == "LEFT" ]]; then 
    ((ZTUI_MENUBAR_ACTIVE_INDEX--))
    if (( ZTUI_MENUBAR_ACTIVE_INDEX < 0 )); then 
      ZTUI_MENUBAR_ACTIVE_INDEX=$((num_items - 1))
    fi
  elif [[ "$DIRECTION" == "RIGHT" ]]; then 
    ((ZTUI_MENUBAR_ACTIVE_INDEX++))
    if (( ZTUI_MENUBAR_ACTIVE_INDEX >= num_items )); then 
      ZTUI_MENUBAR_ACTIVE_INDEX=0
    fi
  fi
  ztui_log "DEBUG" "Menubar active index changed to: $ZTUI_MENUBAR_ACTIVE_INDEX"
}

# Prepares data for opening a submenu
ztui_open_submenu() {
    local MENU_ITEMS_ASSOC_NAME="$1" # Name of the main menu associative array
    # Zsh arrays are 1-indexed for element access ${array[idx]}, 0-indexed for arithmetic
    local active_item_name="${ZTUI_MENUBAR_ITEM_ORDER[$((ZTUI_MENUBAR_ACTIVE_INDEX + 1))]}" 
    
    # Use parameter indirection to get the value (submenu string) from the associative array
    local submenu_string="${(P)${MENU_ITEMS_ASSOC_NAME}[$active_item_name]}"
    
    if [[ -z "$submenu_string" ]]; then 
        ztui_log "INFO" "No submenu items defined for menu item '$active_item_name'."
        return
    fi

    ZTUI_SUBMENU_ITEMS=("${(@s/ /)submenu_string}") # Split string by space into array
    ZTUI_SUBMENU_ACTIVE=1
    ZTUI_SUBMENU_ACTIVE_ITEM_INDEX=0 # Reset submenu selection to first item
    ztui_log "INFO" "Opening submenu for '$active_item_name'. Items: ${(j.,. )ZTUI_SUBMENU_ITEMS}"
}

# Closes an active submenu
ztui_close_submenu() {
    if (( ZTUI_SUBMENU_ACTIVE == 1 )); then 
        ZTUI_SUBMENU_ACTIVE=0
        ZTUI_SUBMENU_ITEMS=() # Clear submenu items
        ztui_log "INFO" "Submenu closed."
        # A full clear/redraw is necessary to remove the submenu box and restore underlying content.
        # This will be handled by the main loop redrawing everything.
        zcurses clear stdscr redraw 
    fi
}

# Draws the currently active submenu (box and items)
# This function is still needed here as it's about drawing a specific widget.
ztui_draw_submenu() {
    if (( ZTUI_SUBMENU_ACTIVE == 0 || ${#ZTUI_SUBMENU_ITEMS[@]} == 0 )); then
        return
    fi

    # Submenu is drawn relative to the content area (inside the main border)
    # Top border is y=0. Content area for widgets starts at y=1, x=1.
    local submenu_draw_y_on_screen=1 # Line below the top border
    local submenu_draw_x_on_screen=$ZTUI_SUBMENU_PARENT_ITEM_X_ON_SCREEN 
    
    if (( submenu_draw_x_on_screen < 1 )); then submenu_draw_x_on_screen=1; fi # Ensure it's within content area

    local max_item_width=0; local item
    for item in "${ZTUI_SUBMENU_ITEMS[@]}"; do 
        if (( ${#item} > max_item_width )); then max_item_width=${#item}; fi
    done
    
    local submenu_content_text_width=$((max_item_width)) 
    local submenu_box_width=$((submenu_content_text_width + 2 + 2)) # text + 2 spaces padding + 2 border lines
    local submenu_box_height=$((${#ZTUI_SUBMENU_ITEMS[@]} + 2)) # Items + top/bottom border

    # Ensure submenu box fits within the main content area
    local max_content_x_coord=$((ZTUI_SCREEN_COLS - 2 -1)) # Max X for start of box (0-indexed)
    local max_content_y_coord=$((ZTUI_SCREEN_LINES - 2 -1)) # Max Y for start of box (0-indexed)

    if (( submenu_draw_x_on_screen + submenu_box_width -1 > max_content_x_coord )); then # -1 because width is a count
        submenu_draw_x_on_screen=$((max_content_x_coord - submenu_box_width + 1))
        if (( submenu_draw_x_on_screen < 1 )); then submenu_draw_x_on_screen=1; fi 
    fi

    local effective_box_height=$submenu_box_height
    if (( submenu_draw_y_on_screen + submenu_box_height -1 > max_content_y_coord )) { 
        effective_box_height=$((max_content_y_coord - submenu_draw_y_on_screen + 1))
        if (( effective_box_height < 3 )) { 
             ztui_log "ERROR" "Submenu cannot be drawn, not enough vertical space. Calculated height $effective_box_height"
             ztui_close_submenu # Close it if it can't be drawn reasonably
             return
        }
        ztui_log "WARN" "Submenu height truncated from $submenu_box_height to $effective_box_height to fit screen."
    }

    # ztui_draw_box is from core_drawing.zsh
    ztui_draw_box $submenu_draw_y_on_screen $submenu_draw_x_on_screen $effective_box_height $submenu_box_width

    local current_item_y_in_box=$((submenu_draw_y_on_screen + 1))
    local current_item_x_in_box=$((submenu_draw_x_on_screen + 1)) 
    local idx=0
    for item in "${ZTUI_SUBMENU_ITEMS[@]}"; do
        if (( idx >= effective_box_height - 2 )); then 
            ztui_log "DEBUG" "Submenu item drawing stopped due to box height limit."
            break
        fi

        zcurses move stdscr $current_item_y_in_box $current_item_x_in_box
        
        if [[ $idx -eq $ZTUI_SUBMENU_ACTIVE_ITEM_INDEX ]]; then # Highlighting active submenu item
             zcurses attr stdscr "$ZTUI_ATTR_MENUBAR_ACTIVE"
        else
             zcurses attr stdscr "$ZTUI_ATTR_MENUBAR_NORMAL"
        fi
        
        local text_to_draw=" $item " # Add one space padding around item text
        # Pad with spaces to fill the width inside the box for consistent highlighting
        local padded_text_to_draw="${text_to_draw}${(pl.$((submenu_box_width - 2 - ${#text_to_draw})).. .)}"
        zcurses string stdscr "$padded_text_to_draw"
        
        ((current_item_y_in_box++))
        ((idx++))
    done
    zcurses attr stdscr "$ZTUI_ATTR_MENUBAR_NORMAL" # Reset attribute after drawing all items
    ztui_log "DEBUG" "Submenu drawn at screen (y,x): $submenu_draw_y_on_screen, $submenu_draw_x_on_screen."
}
