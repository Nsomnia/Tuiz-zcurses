# File: core_screen.zsh
# Overview: Core functions for managing the screen using zsh/curses.
# Handles main application border and top line with menu/title.

################################################################################
# Guard against direct execution
################################################################################
if [[ "$0" == "$ZSH_SCRIPT" ]]; then
    print -u2 "Error: This script ($0) is a library and should be sourced, not executed directly."
    exit 1
fi

################################################################################
# Module Loading
################################################################################
zmodload zsh/curses
if [[ $? -ne 0 ]]; then
  print -u2 "FATAL Error (core_screen.zsh): Command 'zmodload zsh/curses' failed."
  return 1
fi

################################################################################
# Screen Initialization and Configuration
################################################################################
ztui_init_screen() {
  ztui_log "DEBUG" "Initializing screen..."
  zcurses init
  if [[ $? -ne 0 ]]; then 
    print -u2 "Error (ztui_init_screen): 'zcurses init' failed."
    ztui_log "ERROR" "'zcurses init' failed."
    return 1
  fi
  ztui_log "INFO" "zcurses initialized."

  echoti civis 
  if [[ $? -ne 0 ]]; then ztui_log "WARN" "'echoti civis' failed. Cursor might remain visible."; fi

  typeset -g ZTUI_SCREEN_LINES ZTUI_SCREEN_COLS
  ZTUI_SCREEN_LINES=${LINES}
  ZTUI_SCREEN_COLS=${COLUMNS}

  if ! [[ "$ZTUI_SCREEN_LINES" =~ ^[0-9]+$ && "$ZTUI_SCREEN_LINES" -ge 3 && \
          "$ZTUI_SCREEN_COLS" =~ ^[0-9]+$ && "$ZTUI_SCREEN_COLS" -ge 40 ]]; then 
      local err_msg="Invalid/Too small screen dimensions (LINES: '$ZTUI_SCREEN_LINES', COLS: '$ZTUI_SCREEN_COLS'). Min 3x40 required."
      print -u2 "Error (ztui_init_screen): $err_msg"
      ztui_log "ERROR" "$err_msg"
      echoti cnorm 
      zcurses end 
      return 1
  fi
  ztui_log "INFO" "Screen dimensions: LINES=$ZTUI_SCREEN_LINES, COLS=$ZTUI_SCREEN_COLS"

  zcurses clear stdscr redraw 
  if [[ $? -ne 0 ]]; then ztui_log "WARN" "'zcurses clear stdscr redraw' failed."; fi
  
  ztui_draw_main_app_sides_bottom_border # From core_drawing.zsh

  ztui_log "DEBUG" "Screen initialized (sides/bottom border drawn)."
  return 0
}

# Function to draw the top border line, incorporating menu and title.
ztui_draw_top_border_with_menu_title() {
    local TITLE_TEXT="$1"
    # Assumes ZTUI_MENUBAR_ITEM_ORDER, ZTUI_MENUBAR_ACTIVE_INDEX, ZTUI_SUBMENU_ACTIVE are global
    # Assumes ZTUI_ATTR_MENUBAR_NORMAL, ZTUI_ATTR_MENUBAR_ACTIVE are global
    # Assumes ZTUI_MAIN_BORDER_H, ZTUI_MAIN_BORDER_UL, ZTUI_MAIN_BORDER_UR are global

    local y_coord=0 
    local border_x_start=0
    local border_effective_width=$((ZTUI_SCREEN_COLS - 1)) 

    ztui_log "DEBUG" "Drawing top border: y=$y_coord, effective_w=$border_effective_width, title='$TITLE_TEXT'"
    
    zcurses attr stdscr "$ZTUI_ATTR_MENUBAR_NORMAL" 

    zcurses move stdscr $y_coord $border_x_start
    zcurses string stdscr "$ZTUI_MAIN_BORDER_UL"

    local current_x=$((border_x_start + 1)) 
    local available_inner_width=$((border_effective_width - 2)) 

    # 1. Draw Menu Items directly here
    local menu_idx=0
    local menu_item_name
    local menu_items_drawn_total_width=0

    ztui_log "DEBUG" "MENUBAR_ITEM_ORDER: (${ZTUI_MENUBAR_ITEM_ORDER[*]}). Active Index: $ZTUI_MENUBAR_ACTIVE_INDEX. Submenu Active: $ZTUI_SUBMENU_ACTIVE"

    for menu_item_name in "${ZTUI_MENUBAR_ITEM_ORDER[@]}"; do
        ztui_log "DEBUG" "Menu Loop: item_name='$menu_item_name', menu_idx=$menu_idx, current_x=$current_x"
        local prefix="$ZTUI_MAIN_BORDER_H" 
        local suffix="$ZTUI_MAIN_BORDER_H" 
        local item_text_formatted=""

        if [[ $menu_idx -eq $ZTUI_MENUBAR_ACTIVE_INDEX && $ZTUI_SUBMENU_ACTIVE -eq 0 ]]; then
            item_text_formatted="[${menu_item_name}]" # Active: [Item]
            ZTUI_SUBMENU_PARENT_ITEM_X_ON_SCREEN=$((current_x + ${#prefix})) 
        else
            item_text_formatted="${menu_item_name}"   # Non-active: Item
        fi
        
        local display_item_segment="${prefix}${item_text_formatted}${suffix}"
        local display_item_segment_len=${#display_item_segment}
        ztui_log "DEBUG" "Menu item segment to draw: '$display_item_segment', len: $display_item_segment_len"


        local min_space_for_title_part=$(( ${#TITLE_TEXT} + 5 )) 
        if (( current_x + display_item_segment_len > available_inner_width - min_space_for_title_part )); then
            ztui_log "DEBUG" "Menu item '$menu_item_name' (segment len $display_item_segment_len) won't fit with title. Stopping menu draw at x=$current_x."
            break 
        fi

        if [[ $menu_idx -eq $ZTUI_MENUBAR_ACTIVE_INDEX && $ZTUI_SUBMENU_ACTIVE -eq 0 ]]; then
            zcurses attr stdscr "$ZTUI_ATTR_MENUBAR_ACTIVE"
        else
            zcurses attr stdscr "$ZTUI_ATTR_MENUBAR_NORMAL"
        fi

        zcurses move stdscr $y_coord $current_x
        zcurses string stdscr "$display_item_segment"
        ztui_log "DEBUG" "Drew menu item '$menu_item_name' at x=$current_x"
        
        current_x=$((current_x + display_item_segment_len))
        menu_items_drawn_total_width=$((menu_items_drawn_total_width + display_item_segment_len))
        ((menu_idx++))
    done
        
    zcurses attr stdscr "$ZTUI_ATTR_MENUBAR_NORMAL" 

    # 2. Draw Title and remaining dashes
    local title_segment_start_x=$current_x
    local title_segment_end_x=$((border_x_start + border_effective_width - 1)) 
    local space_for_title_and_dashes=$((title_segment_end_x - title_segment_start_x))
    
    ztui_log "DEBUG" "Drawing title segment: start_x=$title_segment_start_x, end_x=$title_segment_end_x, space=$space_for_title_and_dashes"
    zcurses move stdscr $y_coord $current_x 

    if [[ -n "$TITLE_TEXT" && $space_for_title_and_dashes -gt ${#TITLE_TEXT} ]]; then
        local title_len=${#TITLE_TEXT}
        local title_actual_start_x=$((title_segment_start_x + (space_for_title_and_dashes - title_len) / 2))
        
        ztui_log "DEBUG" "Title: '$TITLE_TEXT', len: $title_len, actual_start_x: $title_actual_start_x"

        while (( current_x < title_actual_start_x )); do
            if (( current_x >= title_segment_end_x )); then break; fi 
            zcurses string stdscr "$ZTUI_MAIN_BORDER_H"
            ((current_x++))
        done
        
        if (( current_x + title_len <= title_segment_end_x )); then
            zcurses string stdscr "$TITLE_TEXT" 
            ((current_x += title_len))
        else
            ztui_log "WARN" "Not enough space to draw full title after filling pre-title dashes."
        fi
        
        while (( current_x < title_segment_end_x )); do
            zcurses string stdscr "$ZTUI_MAIN_BORDER_H"
            ((current_x++))
        done
    else
        ztui_log "DEBUG" "No title or not enough space for title. Filling with dashes."
        while (( current_x < title_segment_end_x )); do
            zcurses string stdscr "$ZTUI_MAIN_BORDER_H"
            ((current_x++))
        done
    fi
    
    zcurses move stdscr $y_coord $((border_x_start + border_effective_width - 1))
    zcurses string stdscr "$ZTUI_MAIN_BORDER_UR"

    zcurses attr stdscr "$ZTUI_ATTR_MENUBAR_NORMAL"
    ztui_log "DEBUG" "Top border drawn, final current_x=$current_x"
}

ztui_end_screen() {
  ztui_log "DEBUG" "Ending screen session..."
  if zmodload -L zsh/curses >/dev/null 2>&1; then
      echoti cnorm
      if [[ $? -ne 0 ]]; then ztui_log "WARN" "'echoti cnorm' failed to restore cursor."; fi
      zcurses end
      ztui_log "INFO" "zcurses ended."
  else
      ztui_log "WARN" "zsh/curses module not loaded at ztui_end_screen."
  fi
}

ztui_refresh_screen() {
  zcurses refresh stdscr 
  if [[ $? -ne 0 ]]; then
      ztui_log "WARN" "'zcurses refresh stdscr' failed. Trying 'zcurses refresh'."
      zcurses refresh 
      if [[ $? -ne 0 ]]; then ztui_log "ERROR" "'zcurses refresh' also failed."; return 1; fi
  fi
}
