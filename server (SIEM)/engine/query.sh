#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

source "$ROOT_DIR/config/config.conf"
LOGFILE="${TARGET_LOG:-$ROOT_DIR/$EVENT_LOG}"

read -r -a QUERY <<< "$*"

FILTER="true"
MODE="AND"

for token in "${QUERY[@]}"
do
    case "$token" in

        AND)
            MODE="AND"
        ;;

        OR)
            MODE="OR"
        ;;

        NOT)
            MODE="NOT"
        ;;

        *=*)
            field=$(echo "$token" | cut -d= -f1)
            value=$(echo "$token" | cut -d= -f2)

            if [[ "$value" == "*" ]]; then
                condition="has(\"$field\") or (.data | has(\"$field\"))"
            else
                condition=".data.$field == \"$value\" or .$field == \"$value\""
            fi

            if [ "$MODE" = "AND" ]; then
                FILTER="$FILTER and ($condition)"
            elif [ "$MODE" = "OR" ]; then
                FILTER="$FILTER or ($condition)"
            elif [ "$MODE" = "NOT" ]; then
                FILTER="$FILTER and (not ($condition))"
            fi
        ;;

        *)
            pattern=$(echo "$token" | sed 's/\*/.*/g')

            FILTER="$FILTER and (tostring | test(\"$pattern\"; \"i\"))"
        ;;

    esac
done

jq "select($FILTER)" "$LOGFILE"
