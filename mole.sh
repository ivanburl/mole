#!/usr/bin/env sh

#configurations
EDITOR="${EDITOR:-${VISUAL:-vi}}"
MOLE_RC="${MOLE_RC}"
NSEC_IN_SEC=1000000000
# [DESCRIPTION]
# returns an error with code 1 and description
error() {
  echo "Error occurred. Description: $1"
  exit 1
}

help() {
  echo "help"
}

# [number1] [number2]
integer_max() {
  if [ "$1" -gt "$2" ]; then
    echo "$1"
  else
    echo "$2"
  fi
}

# args:
# FILE - file to gen absolute path
get_absolute_path() {
  if ! [ -e "$1" ]; then
    error "Given path $1 does not exist"
  fi
  readlink -f "$1"
}

get_current_time() {
  date +%s%N
}

# args: FILE - file to check
get_edited_file_time() {
  date -r "$1" +%s%N
}

#[STRING]
date_to_nanoseconds() {
  if ! date -d "$1" +%s%N; then
    error "Incorrect date format. Given $1, expected yyyy-mm-dd."
  fi
}

#[NANOSECONDS]
nanoseconds_to_date() {
  if ! date -d @"$(($1 / $NSEC_IN_SEC))" +'%Y-%m-%d_%H-%M-%S'; then
    error "Cant convert nanoseconds to the date."
  fi
}

check_mole_rc() {
  if ! [ -e "$MOLE_RC" ]; then
    error "MOLE_RC is set"
  fi

  if ! [ -f "$MOLE_RC" ]; then
    error "MOLE_RC=$MOLE_RC should be file"
  fi

  if ! [ -w "$MOLE_RC" ]; then
    error "MOLE_RC=$MOLE_RC should be writable file"
  fi

  if ! [ -r "$MOLE_RC" ]; then
    error "MOLE_RC=$MOLE_RC should be readable file"
  fi
}

# [FILE]
create_path_with_file() {
  if ! [ -e "$1" ]; then
    if ! [ "$(mkdir -p "$(dirname "$1")" && touch "$1")" ]; then
      error "Could not create path MOLE_RC=\"$MOLE_RC\"! Try to change MOLE_RC value."
    fi
  fi

  if ! [ -f "$1" ]; then
    error "MOLE_RC should be path to the file!"
  fi
}

# [FILE] [GROUP]
open_file_mole_rc() {
  #todo how to end file
  _opened=$(get_current_time)
  if [ -d "$1" ]; then
    open_directory_mole_rc "$1" "$2" "" "" ""
    return
  else

    if ! "$EDITOR" "$1"; then
      error "Editor threw an error."
    fi

    if [ -e "$1" ]; then
      _edited=$(get_edited_file_time "$1")
      write_mole_rc "$(get_absolute_path "$1")" "$2" "$(integer_max "$_opened" "$_edited")"
    fi

  fi
}

#[FILE_REG_EXPR] [GROUPS] [N_START_DATE] [N_END_DATE]
filter_mole_rc() {
  awk -F";" \
  -v dir_exp="$1" -v groups="$2" \
  -v start_date="$3" -v end_date="$4" \
  '
    BEGIN {
      split(groups, group_arr, ",");
    }
    {
      good = 0
      if ($1 ~ dir_exp)
      {
        find_group = 0
        for (key in group_arr) {
          if (group_arr[key]!="" && group_arr[key]==$2) { find_group = 1; break; }
        }

        for (i=3;i<=NF && find_group==1;i++)
        {
          if ((start_date=="" || $i+0>=start_date+0) &&
              (end_date=="" || $i+0<=end_date+0))
          {
            good = 1;
            break;
          }
        }
        if (good) print $0
      }
    }' \
  "$MOLE_RC"
}

#[DIRECTORY] [GROUPS] [N_START_DATE] [N_END_DATE] [M_FLAG]
open_directory_mole_rc() {
  _tmp="$( #TODO read speciifcations of directory search add ^$1[^\/]+\$
    filter_mole_rc "$1" "$2" "$3" "$4" | awk -F";" \
    -v m_flag="$5" \
    '
    BEGIN {
      file = ""
      group = ""
      max = 0
    }
    {
      if (m_flag==1) {
        if (max < NF) {
          max = NF;
          file=$1;
          group=$2;
        }
      }
      else {
        for (i=3;i<=NF;i++) {
            if ($i+0>max) {
              max = $i+0;
              file=$1;
              group=$1;
            }
        }
      }
    }
    END {
      if (file != "") print file
      if (group != "") print group
    }' \
    "$MOLE_RC"
  ) "

  if ! [ "$(echo "$_tmp" | wc -l)" -eq 2 ]; then
    error "Could not find the file, which suits filters."
  fi

  open_file_mole_rc "$(echo "$_tmp" | sed "1q;d")" "$(echo "$_tmp" | sed "2q;d")"
}

# [DIRECTORY] [GROUPS] [START_DATE] [END_DATE]
list_info_mole_rc() {
    filter_mole_rc "$1" "$2" "$3" "$4" | awk -F";" -v OFS=";" \
    '
    {
      if (map[$1]=="") map[$1]=$2; else map[$1]=map[$1] "," $2;
    }
    END {
      for (key in map) {
        printf("%s: %s\n", key, map[key]);
      }
    }
    ';
}

# [DIRECTORIES (should be absolute paths)] [START_DATE] [END_DATE]
create_secret_log() {
  if ! [ -d "$1" ]; then
    error "Given path is not directory."
  fi

  awk -F";" -v OFS=';' \
  -v directories="$1" -v start_date="$2" -v end_date="$3" \
  '
  BEGIN {
    split(directories, directory_arr, ";")
  }
  {
    for (key in directory_arr) {
    directory="^" directory_arr[key] "[^\/]+$"
    if ($1 ~ directory) {
      fields = 1
      for(i=3;i<=NF;i++)
      {
        if ((start_date == "" || $i+0 >= start_date+0) && (end_date == "" || $i+0 <= end_date+0)) {
          fields++;
          $fields = strftime("%d-%m-%Y_%H-%M-%S", $i/1000000000);
        }
      }
      NF=fields;
      if (NF>=2) {
        print $0
        break;
      }
    }
    }
  }' "$MOLE_RC"
}

# args:
# FILE - path to the file
# GROUP - group of the file
# DATE - date in nanoseconds
write_mole_rc() {
  _tmp_file=$(mktemp) #FIXME mktemp is not POSIX compliant
  awk -F";" -v OFS=';' \
  -v name="$1" -v group="$2" -v date="$3" \
  '
      BEGIN { found = 0; }
      {
        if ($1==name && $2==group) {
          found=1;
          print $0, date
        } else {
          print $0
        }
      }
      END { if (found == 0) print name,group,date }
      ' \
  "$MOLE_RC" >"$_tmp_file"
  mv "$_tmp_file" "$MOLE_RC"
}

################################# READ_OF_ARGS #######################################
a_flag="" # date type
b_flag="" # date type
h_flag=0  # help flag
g_flag="" # string type (collection fo strings in string)
m_flag=0  # flag to open file which is opened mostly
d_flag=0  # default group flag

list_flag=0
secret_log_flag=0

case $1 in
list) list_flag=1 ;;
secret-log) secret_log_flag=1 ;;
esac

if [ "$list_flag" -eq 0 ] || [ "$secret_log_flag" -eq 0 ]; then
  echo "Executed"
  shift
fi

while getopts d:a:b:h:g:m: flag; do
  case "${flag}" in
  d) d_flag=1 ;;
  a) a_flag="$(date_to_nanoseconds "$OPTARG")" ;;
  b) b_flag="$(date_to_nanoseconds "$OPTARG")" ;;
  h) h_flag=1 ;;
  g) g_flag=$OPTARG ;;
  m) m_flag=1 ;;
  *) error "Unknown option: $OPTARG." ;;
  esac
done

shift "$((OPTIND - 1))"

#secret-log processing
if [ $secret_log_flag -eq 1 ]; then

  directories="$1";
  shift;

  while [ "$#" -ne 0 ]; do
    directories=""
  done

  exit 0
fi
#######################

directory=$PWD

if [ "$#" -eq 1 ]; then
  directory=$1
  shift
fi

if [ "$#" -ne 0 ]; then
  error "Incorrect command format. Use -h to get more info."
fi
#######################################################################################

echo "DEBUG: -a $a_flag | -b $b_flag | -g $g_flag | -m $m_flag | -h $h_flag | dir $directory | l_f $list_flag | s_f $secret_log_flag | -d $d_flag"
echo "CONFIGS: rc $MOLE_RC | ed $EDITOR"

#TODO do not forget to disable "" as input
#create_path_with_file "$MOLE_RC"
#filter_files_search_mole_rc "" "" "" ""
#write_mole_rc "test1" "" "$(get_current_time)"
#write_mole_rc "giga1" "" "$(get_current_time)"
#
#open_file_mole_rc "biba" "group"
#create_secret_log "." "" ""

filter_mole_rc "test" "boba,roba" "" ""
list_info_mole_rc "test" "boba,roba" "" ""