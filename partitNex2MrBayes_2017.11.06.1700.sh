#!/bin/bash

########################################################################

THIS_SCRIPT=`basename ${BASH_SOURCE[0]}`
#DESCRIPTION="A bash shell scrip to convert a partitioned NEXUS file into a partitioned MrBayes analysis file"
AUTHOR="Michael Gruenstaeudl, PhD"
#COPYRIGHT="Copyright (C) 2015-2017 $AUTHOR"
#CONTACT="m.gruenstaeudl@fu-berlin.de"
VERSION="2017.10.23.1400"
USAGE="bash $THIS_SCRIPT -f <path_to_NEXUS_file> -c <path_to_config_file> -t <type_of_modeltesting_tool> -b <path_to_modeltesting_tool> -o <path_to_outfile>"

########################################################################

# TO DO:
# (1) Replace multiple instances of sed text replacements (especially the terrible in-line replacements "sed -i") with substitutions using Bash's built-in parameter expansion.

# PAPER: BMC Evol Biol. 2010 Aug 9;10:242. doi: 10.1186/1471-2148-10-242. Performance of criteria for selecting evolutionary models in phylogenetics: a comprehensive study based on simulated datasets. Luo A1, Qiao H, Zhang Y, Shi W, Ho SY, Xu W, Zhang A, Zhu C.
# TELLS THAT BIC SHOULD BE USED FOR MODEL SELECTION.
# 

########################################################################

# INITIAL SETTINGS AND COMMANDLINE INTERFACE

# Toggle on: throw errors
set -e

# Start timing execution time
RUNTIME_start=$(date +%s)
RUNTIME_start_pp=$(date '+%Y.%m.%d.%H%M')

# Initialize variables to default values
OPT_A="name of, and file path to, the input NEXUS file"
OPT_B="name of, and file path to, the input config file"
OPT_C="name of partitionfinding / modeltesting software tool (available: jmodeltest, partitionfinder, partitiontest, sms)"
OPT_D="name of, and file path to, the modeltesting binary or script"
OPT_E="name of, and file path to, the output file"
keepflsBOOL=0
verboseBOOL=0
usrschmBOOL=0

# Set fonts for help function
NORM=`tput sgr0`
BOLD=`tput bold`
REV=`tput smso`

# Help function
function my_help {
    echo -e \\n"Help documentation for ${BOLD}$THIS_SCRIPT${NORM}."\\n
    echo -e "Version: $VERSION | Author: $AUTHOR"\\n
    echo -e "${REV}Usage:${NORM} $USAGE"\\n
    echo "MANDATORY command line switches:"
    echo "${REV}-f${NORM}  --Sets name of, and file path to, ${BOLD}NEXUS file${NORM}. No default exists."
    echo "${REV}-c${NORM}  --Sets name of, and file path to, ${BOLD}config file${NORM}. No default exists."
    echo "${REV}-t${NORM}  --Sets ${BOLD}type${NORM} of partitionfinding / modeltesting software tool. Available: jmodeltest, partitionfinder, partitiontest, sms. No default exists."
    echo "${REV}-b${NORM}  --Sets name of, and file path to, the modeltesting ${BOLD}binary or script${NORM}. No default exists."
    echo "${REV}-o${NORM}  --Sets name of, and file path to, ${BOLD}output file${NORM}. No default exists."
    echo ""
    echo "OPTIONAL command line switches:"
    echo "${REV}-u${NORM}  --Estimating model fit only for the ${BOLD}user-defined${NORM} partitioning scheme. Only applicable for PartitionFinder. Default is ${BOLD}off${NORM}."
    echo "${REV}-k${NORM}  --${BOLD}Keeps${NORM} temporary files. Default is ${BOLD}off${NORM}."
    echo "${REV}-v${NORM}  --Displays ${BOLD}verbose${NORM} status messages. Default is ${BOLD}off${NORM}."
    echo -e "${REV}-h${NORM}  --Displays this help message."\\n
    exit 1
}

# Check the number of arguments. If none are passed, print help and exit.
numArgmts=$#
if [ $numArgmts -eq 0 ]; then
    my_help
fi

########################################################################

# GETOPTS CODE

while getopts :f:c:t:b:o:hukv FLAG; do
  case $FLAG in
    f)  OPT_A=$OPTARG
        ;;
    c)  OPT_B=$OPTARG
        ;;
    t)  OPT_C=$OPTARG
        ;;
    b)  OPT_D=$OPTARG
        ;;
    o)  OPT_E=$OPTARG
        ;;
    h)  my_help
        ;;
    u)  usrschmBOOL=1
        ;;
    k)  keepflsBOOL=1
        ;;
    v)  verboseBOOL=1
        ;;
    \?) echo 'Invalid option: -$OPTARG' >&2
        exit 1
        ;;
    :)  echo 'Option -$OPTARG requires an argument.' >&2
        exit 1
        ;;
  esac
done

#shift $((OPTIND-1))

########################################################################
########################################################################

# GENERAL FUNCTIONS

get_current_time() {
    date '+%Y-%m-%d %Z %H:%M:%S'
}

assemble_mrbayes_block_general()
#   This function appends a MrBayes block to a file ($mbOUTFILE).
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of outfile ($mbOUTFILE)
#         $3: name of file with lset definitions ($lsetDefns)
#         $4: name of file containing the extracted SETS-block ($setsBlock)
#         $5: name of config file ($reformCFG)
#   OUP:  none; operates on lset definitions file
{
    # INTERNAL FUNCTION CHECKS
    (($# == 5)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    charsetLines=$(cat ./$1/$4 | grep 'charset')
    echo -e 'begin mrbayes;' >> $2
    echo "$charsetLines" >> $2
    echo -n 'partition combined =' $(echo "$charsetLines" | wc -l) ': ' >> $2 # Line must not end with linebreak, thus -n
    echo "$charsetLines" | awk '{print $2}' | awk '{ORS=", "; print; }' >> $2
    sed -i 's/\(.*\)\,/\1;/' $2 # Replace final comma with semi-colon; don't make this replacement global
    echo -e '\nset partition = combined;' >> $2 # Option -e means that \n generates new line
    cat ./$1/$3 >> $2
    echo 'prset applyto=(all) ratepr=variable;' >> $2
    echo 'unlink statefreq=(all) revmat=(all) shape=(all) pinvar=(all) tratio=(all);' >> $2
    echo -e 'end;\n' >> $2
}

check_inp_outp_availability()
#   This function checks the availability of input and output files.
#   INP:  $1: path and name of input: NEXUS file ($nexINFILE)
#         $2: path and name of input: CONFIG file ($cfgINFILE)
#         $3: path and name of input: modeltest binary/script ($BinMDLTST)
#         $4: path and name of output file ($mbOUTFILE)
#   OUP:  none
{
    # INTERNAL FUNCTION CHECKS
    (($# == 4)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    # Checking if input files exists
    #if [[ ! -f $1 ]]; then 
    if [ ! -f $1 ]; then 
        echo -ne " ERROR | $(get_current_time) | NEXUS file not found: $1\n"
        exit 1
    fi
    if [ ! -f $2 ]; then 
        echo -ne " ERROR | $(get_current_time) | Config file not found: $2\n"
        exit 1
    fi
    if [ ! -f $3 ]; then 
        echo -ne " ERROR | $(get_current_time) | Modeltest binary/script file not found: $3\n"
        exit 1
    fi
    # Check if outfile already exists
    #if [[ $3 = /* ]]; then # File is generated by GETOPTS, so checking its presence is not useful
    if [ -f $4 ]; then
        echo -ne " ERROR | $(get_current_time) | Outfile already exists in filepath: $4\n"
        exit 1
    fi
}

ensure_partitions_form_continuous_range()
#   This function tests if the partitions form a continuous range. 
#   If the partitions don't form such a continuous range, additional
#   ranges are inserted such that all ranges taken together form a 
#   continuous range from {1} to {total size of matrix}.
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of file containing the SETS-block
#         $3: total size of matrix
#   OUP:  update of $1
{
    # INTERNAL FUNCTION CHECKS
    (($# == 3)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    # Get charset definition lines
    charsetLines=$(sed -n '/begin sets\;/{:a;n;/end\;/b;p;ba}' ./$1/$2 | grep 'charset')
    # Convert from discrete to continuous range
    continuousRange=$(echo "$charsetLines" | awk '{ split($4,curr,/[-;]/); currStart=curr[1]; currEnd=curr[2] } currStart > (prevEnd+1) { print "charset " "new"++cnt " = " prevEnd+1 "-" currStart-1 ";" } { print; prevEnd=currEnd }')
    # Add concluding partition, if missing
    matrxLngth=$3
    closingRange=$(echo "$continuousRange" | tail -n1 | awk -F'[[:space:]]*|-' -v lngth=$matrxLngth ' $5<lngth {print "charset newFinal = " $5+1 "-" lngth ";"}')
    # Update SETS-block
    echo "begin sets;" > ./$1/$2
    echo "$continuousRange" >> ./$1/$2 # NOTE: $continuousRange is a multi-line variable, whose linebreaks shall be maintained; thus, it is passed as doublequote-enclosed.
    if [ -n "$closingRange" ]; then # NOTE: The -n operator checks whether the string is not null.
        echo "$closingRange" >> ./$1/$2
    fi
    echo "end;" >> ./$1/$2
}

get_num_of_avail_cores()
#   This function evaluates the numberof available cores on a system
#   INP:  none
#   OUP:  returns integer
{
    nmbrCores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null)  # NOTE: The "||" indicates that if "nproc" fails, do "grep ^processor /proc/cpuinfo".
    posIntgr='^[0-9]+$'
    if ! [[ $nmbrCores =~ $posIntgr ]]; then
        nmbrCores=1
    fi
    echo $nmbrCores
}

reconstitute_datablock_as_interleaved()
#   This function reconstitutes a data block from individual partitions, but makes the data block interleaved.
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of DATA-block ($dataBlock)
#         $3: name of outfile ($mbOUTFILE)
#         $4: filename prefix
#   OUP:  none; writes to outfile
{
    # INTERNAL FUNCTION CHECKS
    (($# == 4)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    # Step 1: Append dimension and format info of DATA-block
    cat ./$1/$2 | sed -n '/begin data\;/,/matrix/p' >> $3
    # Step 2: Specify that matrix is interleaved
    sed -i '/format/ s/\;/ interleave\=yes\;/' $3 # in-line replacement of semi-colon with interleave-info plus semi-colon, if line has keyword 'format'
    # Step 3: Append the individual partitions
    for p in $(ls ./$1/$4_partition_[0-9]* | grep -v "\.bestModel\|\.phy\|\.runlog\|_sms\.csv"); do # NOTE: Use [0-9] to separate from 'partition_finder.cfg'
        echo -ne "\n[$(basename $p)]\n" >> $3
        pureMatrix=$(cat $p | sed -n '/matrix/{:a;n;/;/b;p;ba}')
        algnMatrx=$(echo "$pureMatrix" | column -t)
        echo "$algnMatrx" >> $3 # Append only the matrix of a partition, not the preceeding dimension and format info; also, don't append the closing ';\nend;' per partition
    done
    # Step 4: Append a closing ';\nend;'
    echo -e "\n;\nend;" >> $3
}

reformat_config_file()
#   This function performs the following steps:
#   (a) it removes comments from a CONFIG file,
#   (b) it removes blank lines (both blank by whitespaces and by tabs),
#   (c) it removes the configurations of modeltesting types not selected.
#   INP:  $1: name of complete CONFIG file ($cfgINFILE)
#         $2: type of modeltesting selected: ($typMDLTST)
#         $3: name of a reformatted CONFIG file ($tmpFOLDER/$reformCFG)
#   OUP:  the re-formatted CONFIG file
{
    # INTERNAL FUNCTION CHECKS
    (($# == 3)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    ## REMOVES LEADING WHITESPACES FROM EVERY LINE
    #  (so that formatting (i.e., indets) does not matter)
    configWithoutLeadWhitesp=$(sed -e 's/^[ \t]*//' $1)
    
    ## REMOVES COMMENTS FROM A CONFIG FILE
    #  (i.e., delete all info that starts with a pound sign)
    configWithoutComments=$(echo "$configWithoutLeadWhitesp" | grep -v "^#")

    ## REMOVES BLANK LINES
    #  (both blank by whitespaces and by tabs)
    configWithoutBlankLines=$(echo "$configWithoutComments" | sed '/^\s*$/d')
    
    ## KEEP ONLY CONFIGURATION OF MODELTEST TYPE SELECTED
    configOnlyTypeSelected=$(echo "$configWithoutBlankLines" | grep -A1 --ignore-case --no-group-separator "\%$2\|\%mrbayes")
    
    echo "$configOnlyTypeSelected" > $3
}

reformat_nexus_file()
#   This function performs the following steps:
#   (a) it removes comments from a NEXUS file,
#   (b) it removes blank lines (both blank by whitespaces and by tabs), 
#   (c) it standardizes critical command lines (i.e. begin data, 
#       begin sets, dimensions, etc.) as lowercase, and
#   (d) it removes lines from the sets-block that do not start with the keyword "charset"
#   INP:  $1: name of complete NEXUS file ($nexINFILE)
#         $2: name of a reformatted NEXUS file ($tmpFOLDER/$reformNEX)
#   OUP:  the re-formatted NEXUS file
{
    # INTERNAL FUNCTION CHECKS
    (($# == 2)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    ## REMOVES COMMENTS FROM A NEXUS FILE
    #  (i.e., delete all info enclosed by square brackets)
    nexusWithoutComments=$(sed 's/\[[^]]*\]//g' $1)

    ## REMOVES BLANK LINES
    #  (both blank by whitespaces and by tabs)
    nexusWithoutBlankLines=$(echo "$nexusWithoutComments" | sed '/^\s*$/d')

    ## REMOVES LEADING WHITESPACES FROM EVERY LINE
    #  (so that formatting (i.e., indets) does not matter)
    nexusWithoutLeadWhitesp=$(echo "$nexusWithoutBlankLines" | sed -e 's/^[ \t]*//')

    ## STANDARDIZES CRITICAL COMMAND LINES AS LOWERCASE (i.e., converts 
    ## ENTIRE LINE that starts with a keyword TO LOWERCASE)
    #  NOTE: These conversions to lowercase are critical for the correct 
    #        section identifikation below.
    #  keyword1: "begin", line ends with semi-colon
    #  NOTE: the following command converts "Begin Data;" to "begin data;", not just "begin"!
    reformatForKeyword1=$(echo "$nexusWithoutLeadWhitesp" | awk 'BEGIN{IGNORECASE=1} /^ *begin\>.*; *$/ {$0=tolower($0)} 1')
    #  keyword2: "end;"
    reformatForKeyword2=$(echo "$reformatForKeyword1" | awk 'BEGIN{IGNORECASE=1} /^ *end\;/ {$0=tolower($0)} 1')
    #  keyword3: "matrix"
    reformatForKeyword3=$(echo "$reformatForKeyword2" | awk 'BEGIN{IGNORECASE=1} /^ *matrix\>/ {$0=tolower($0)} 1')
    #  keyword4: "dimensions", line ends with semi-colon
    reformatForKeyword4=$(echo "$reformatForKeyword3" | awk 'BEGIN{IGNORECASE=1} /^ *dimensions\>.*; *$/ {$0=tolower($0)} 1')
    #  keyword5: "format", line ends with semi-colon
    reformatForKeyword5=$(echo "$reformatForKeyword4" | awk 'BEGIN{IGNORECASE=1} /^ *format\>.*; *$/ {$0=tolower($0)} 1')
    #  Convert only specific keyword to lowercase
    reformatForKeyword6=$(echo "$reformatForKeyword5" | awk 'tolower($1)=="charset"{$1=tolower($1)}1')

    ## SORT CHARSETS
    charsetLines=$(echo "$reformatForKeyword6" | sed -n '/begin sets\;/{:a;n;/end\;/b;p;ba}' | grep 'charset')
    charsetLinesSorted=$(echo "$charsetLines" | sort -t'=' -k2n)
    
    ## REMOVES LINES FROM THE SETS-BLOCK THAT DO NOT START WITH THE KEYWORD "CHARSET"
    #  NOTE: This check must come after the conversion to lowercase chars!
    #  NOTE: This step generates the outfile (i.e., reformatted NEXUS file)
    echo -e "#NEXUS\n" > $2
    echo "$reformatForKeyword6" | sed -n '/begin data\;/,/end\;/p' >> $2
    echo -e "\nbegin sets;" >> $2
    echo "$charsetLinesSorted" >> $2
    echo "end;" >> $2

    ## CHECK THAT DATATYPE IS "DNA|dna"
    #  NOTE: This check must come after the conversion to lowercase chars!
    dataTypeB=$(cat $2 | grep format | sed -n 's/.*datatype=\([^ ]*\).*/\1/p') # Extract info on datatype
    if [ ! "$dataTypeB" = "dna" ]; then
        echo -ne " ERROR | $(get_current_time) | Datatype not set as: DNA\n"
        exit 1
    fi
}

split_matrix_into_partitions()
#   This function takes the matrix of a NEXUS file and extracts from it a 
#   character range (hereafter "sub-matrix") specified by charsets line 
#   definitions.
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of file containing the DATA-block
#         $3: name of file containing the SETS-block
#         $4: outname prefix
#   OUP:  file with name $partitnFn in temp folder
{
    # INTERNAL FUNCTION CHECKS
    (($# == 4)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    pureMatrix=$(sed -n '/matrix/{:a;n;/;/b;p;ba}' ./$1/$2)
    charsetLns=$(sed -n '/begin sets\;/{:a;n;/end\;/b;p;ba}' ./$1/$3 | grep 'charset')
    dimensnLns=$(sed -e '/matrix/,$d' ./$1/$2) # Get section between "#NEXUS" and "MATRIX"
    partitionCounter=0
    while IFS= read -r line; do 
        partitionCounter=$((partitionCounter+1))
        partitFn1=$(printf %04d $partitionCounter)
        partitFn2=$(echo "$line" | awk '{print $2}')
        partitnFn=$4_partition_${partitFn1}_${partitFn2}
        # Get the info on the charset range
        charsetRanges=$(echo "$line" | awk '{print $4}' | sed 's/\;//')
        
        # Assembling the new partition file
        echo -e "#NEXUS\n \n$dimensnLns \nmatrix" > ./$1/$partitnFn

        # EXTRACT THE MATRIX OF A NEW PARTITION
        # EXPLANATION: This awk-command takes one or more charset-ranges (which are separated by whitespaces), extracts the respective submatrices from the pureMatrix and concatenates them to a new matrix (i.e., to ./$1/$newPartitnFn).
        awk 'NR==FNR{for(i=1;i<=NF;i++) {split($i,x,"-"); start[i]=x[1]; end[i]=x[2]}; print ""; n=NF; next} {printf "%s", $1 FS; for(i=1;i<=n;i++) printf "%s", substr($2,start[i],end[i]-start[i]+1); print ""}' <(echo "$charsetRanges") <(echo "$pureMatrix") | sed '/^\s*$/d' >> ./$1/$partitnFn
        # LEGACYCODE: The following legacycode could only handle one charrange per charset.
        #awk 'NR==FNR{start=$1;lgth=$2-$1+1;next} {print $1, substr($2,start,lgth)}' FS='-' <(echo "$charsetRanges") FS=' ' <(echo "$pureMatrix") >> ./$1/$partitnFn
        
        # Assembling the new partition file
        echo -e ";\nend;\n" >> ./$1/$partitnFn
        
        # Get the length of the sub-matrix
        #mtrxLngth=$(awk '{print $2-$1+1}' FS='-' <(echo "$charsetRanges"))
        mtrxLngth=$(cat ./$1/$partitnFn | grep -A1 "matrix" | head -n1 | wc -c)
        # Replace the number of characters with the length of the sub-matrix
        sed -i "/dimensions / s/nchar\=.*\;/nchar\=$mtrxLngth\;/" ./$1/$partitnFn
    done <<< "$charsetLns" # Using a here-string
}

split_nexus_into_blocks()
#   This function splits a NEXUS file into individual blocks.
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of reformatted NEXUS file ($reformNEX)
#         $3: name of file containing the extracted DATA-block ($dataBlock)
#         $4: name of file containing the extracted SETS-block ($setsBlock)
#   OUP:  file with DATA-block
#         file with SETS-block
{
    # INTERNAL FUNCTION CHECKS
    (($# == 4)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    # EXTRACT THE BLOCKS
    cat ./$1/$2 | sed -n '/begin data\;/,/end\;/p' > ./$1/$3
    cat ./$1/$2 | sed -n '/begin sets\;/,/end\;/p' > ./$1/$4
    # CHECK IF DATABLOCK SUCCESSFULLY GENERATED
    if [ ! -s "./$1/$3" ]; then
        echo -ne " ERROR | $(get_current_time) | No file size: ./$1/$3\n"
        exit 1
    fi
    # CHECK IF SETSBLOCK SUCCESSFULLY GENERATED
    if [ ! -s "./$1/$4" ]; then
        echo -ne " ERROR | $(get_current_time) | No file size: ./$1/$4\n"
        exit 1
    fi
}

test_if_partitions_overlap()
#   This function tests if any of the partitions (i.e., charset ranges)
#   overlap. If they do, an error is thrown.
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of file containing the SETS-block
#   OUP:  none
{
    # INTERNAL FUNCTION CHECKS
    (($# == 2)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    charsetLines=$(sed -n '/begin sets\;/{:a;n;/end\;/b;p;ba}' ./$1/$2 | grep 'charset')
    charsetRanges=$(echo "$charsetLines" | awk -F"=" '{print $2}' | sed 's/\;//')
    # Test if any of the charset ranges are overlapping
    charsetOverlap=$(echo "$charsetRanges" | awk -F"-" 'Q>=$1 && Q{print val}{Q=$NF;val=$0}')
    if [ ! "$charsetOverlap" = "" ]; then 
        echo -ne " ERROR | $(get_current_time) | Charset range overlaps with subsequent range: $charsetOverlap\n"
        exit 1
    fi
}

########################################################################
########################################################################

# FUNCTIONS USED IN MULTIPLE CASES

assemble_new_nexus_from_new_partitions()
#   This function rearranges matrix-blocks to conform to the new charset lines
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: filename of DATA-block ($dataBlock)
#         $3: file prefix
#         $4: name of outfile ($newNexFil)
#   OUP:  write to the outfile
{
    # INTERNAL FUNCTION CHECKS
    (($# == 4)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done

    # COMBINE NEW PARTITIONS TO NEW MATRIX
    count=$(ls -1 ./$1/$3_partition_[0-9]* 2>/dev/null | wc -l)
    if [ $count != 0 ]; then
        awk '{print $1 " "}' ./$1/$3_partition_0001_* > ./$1/reconstitutedMatrix # Add only seqnames to matrix, not partition
        touch ./$1/reconstitutedCharsets
        nucleotideCounter=0
        for newPartit in ./$1/$3_partition_[0-9]*; do
            # DEALING WITH CHARSET LINES
            partitionMatrix=$(cat $newPartit | awk '{print $2}' | sed -e 's/^[ \t]*//') # NOTE: "sed -e 's/^[ \t]*//'" removes leading whitespaces
            charsetLine=$(echo "charset ")
            charsetLine+=$(echo $(basename $newPartit) | awk -F"_" '{print $3}')
            if [ $nucleotideCounter -eq 0 ]; then # NOTE: Counting starts at zero for length measurement, but at 1 for index positions
                charsetLine+=$(echo " = 1-")
            else
                charsetLine+=$(echo " = $((nucleotideCounter+1))-")
            fi
            partition_length=$(echo "$partitionMatrix" | head -n1 | wc -c)
            nucleotideCounter=$((nucleotideCounter+$partition_length-1))
            charsetLine+=$(echo "$nucleotideCounter;")
            echo "$charsetLine" >> ./$1/reconstitutedCharsets
            # APPENDING (AND GROWING) THE MATRIX
            matrixHandle=$(paste -d'\0' ./$1/reconstitutedMatrix <(echo "$partitionMatrix")) # NOTE: '\0' is defined as null delimiter (i.e., no character) by POSIX
            echo "$matrixHandle" > ./$1/reconstitutedMatrix
        done
    else
        echo -ne " ERROR | $(get_current_time) | No new partition files (i.e., xyz_partition_1234) found.\n"
        exit 1
    fi
    
    # RECONSTITUTE NEW NEXUS-FILE
    echo -e "#NEXUS\n" > $4
    # Write DATA-block
    cat ./$1/$2 | sed -n '/begin data\;/,/matrix/p' >> $4
    column -t ./$1/reconstitutedMatrix >> $4
    echo -e ";\nend;\n" >> $4
    # Write SETS-block
    echo "begin sets;" >> $4
    cat ./$1/reconstitutedCharsets >> $4
    echo "end;" >> $4
}

convert_datablock_to_phylip()
#   This function converts a NEXUS-formatted DATA-block to a PHYLIP-file.
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of reformatted NEXUS file ($reformNEX)
#         $3: filename of DATA-block ($dataBlock)
#         $4: number of characters in DNA matrix ($ncharVar)
#         $5: name of outfile ($phylipFil)
#   OUP:  writes a phylip-formatted file to disk
{
    # INTERNAL FUNCTION CHECKS
    (($# == 5)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    # Extract number of taxa
    ntaxVar=$(grep ^dimensions $1/$2 | sed -n 's/.*ntax=\([^ ]*\).*/\1/p') # NOTE: Terminating the search for ntax=xx with a space means that ntax has to come before nchar in dimensions line.
    
    # Write ntax and nvar to first line of phylip file
    echo "$ntaxVar $4" > ./$1/$5
    
    # Extract matrix from DATA-block
    pureMatrix=$(sed -n '/matrix/{:a;n;/;/b;p;ba}' ./$1/$3)
    #algnMatrx=$(echo "$pureMatrix" | column -t)
    #echo "$algnMatrx" >> ./$1/$5
    echo "$pureMatrix" >> ./$1/$5
}

convert_models_into_lset()
#   This function converts the names of nucleotide substitution models 
#   into lset definitions readable by MrBayes.
#   NOTE: It also adds the model names as comments to the end of each 
#   lset line to allow the applyto-assignment (at the end of the function)!
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of file with best models ($bestModls)
#         $3: name of file with lset definitions file ($lsetDefns)
#         $4: name of file containing the extracted SETS-block ($setsBlock)
#   OUP:  none; operates on lset definitions file
#   NOTE:   The model abbreviation (e.g., `GTR+I+G`) must be at the line 
#           end and no whitespace must come thereafter. This end of line 
#           position precludes that string `GTR+I+G` would be replaced by 
#           `GTR+I`.
{
    # INTERNAL FUNCTION CHECKS
    (($# == 4)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    if [ ! -f ./$1/$2 ]; then 
        echo -ne " ERROR | $(get_current_time) | File not found: ./$1/$2\n"
        exit 1
    fi

    # STEP 1: Convert the model names to lset definitions
    while read LINE
    do
        partit_name=$(echo "$LINE" | awk '{print $1}')
        model_abbrv=$(echo "$LINE" | awk '{print $2}' | awk -F'+' '{print $1}')
        model_invgm=$(echo "$LINE" | awk '{print $2}' | awk -F'+' '{print $1=""; gsub(" ","+"); print $0}' | tr -d '\n')
        
        # DNA SUBSTITUTION MODEL
        if [ "$model_abbrv" == "GTR" ]; then
            PRELINE=$(echo "lset applyto=() nst=6 [INVGM_PLACEHOLDER]")
        elif [ "$modelKeyw" == "SYM" ]; then 
            PRELINE=$(echo "lset applyto=() nst=6 [INVGM_PLACEHOLDER]\nprset applyto=() statefreqpr=fixed(equal);")
        elif [ "$modelKeyw" == "HKY" -o "$modelKeyw" == "HKY85" ]; then 
            PRELINE=$(echo "lset applyto=() nst=2 [INVGM_PLACEHOLDER]")
        elif [ "$modelKeyw" == "K80" -o "$modelKeyw" == "K2P" ]; then 
            PRELINE=$(echo "lset applyto=() nst=2 [INVGM_PLACEHOLDER]\nprset applyto=() statefreqpr=fixed(equal);")
        elif [ "$modelKeyw" == "F81" ]; then 
            PRELINE=$(echo "lset applyto=() nst=1 [INVGM_PLACEHOLDER]")
        elif [ "$modelKeyw" == "JC" -o "$modelKeyw" == "JC69" ]; then 
            PRELINE=$(echo "lset applyto=() nst=1 [INVGM_PLACEHOLDER]\nprset applyto=() statefreqpr=fixed(equal);")
        else # In case a modelname is not in the above list (e.g., TIM, TPM, TrN in PartitionTest; TN93 with SMS), substitute with the default GTR
            PRELINE=$(echo "lset applyto=() nst=6 [INVGM_PLACEHOLDER]")
        fi
        # INVGAMMA SETTINGS
        if [ "$model_invgm" == "+I" ]; then # IMPORTANT: Don't use quotation marks around variable $model_invgm, to avoid inclusion of newline characters into comparison
            LINE=${PRELINE//\[INVGM_PLACEHOLDER\]/rates\=propinv\;} # Substitution with Bash's built-in parameter expansion;
        elif [ "$model_invgm" == "+G" ]; then
            LINE=${PRELINE//\[INVGM_PLACEHOLDER\]/rates\=gamma\;}
        elif [ "$model_invgm" == "+I+G" -o "$model_invgm" == "+G+I" ]; then
            LINE=${PRELINE//\[INVGM_PLACEHOLDER\]/rates\=invgamma\;}
        else
            LINE=${PRELINE//\[INVGM_PLACEHOLDER\]/\;}
        fi
        
        echo "$LINE [# $partit_name ]" >> ./$1/$3
    done < ./$1/$2

    # STEP 2: Replace the partition names in the lset definitions with the line numbers in the charsets
    # NOTE: THIS IS WHY ORDERED PARTITIONS ARE CRITICAL!
    charsetLines=$(cat ./$1/$4 | grep 'charset')
    for charset in $(echo "$charsetLines" | awk '{print $2}'); do # Use doublequote-enclosing around a variable to maintain its newlines!
        lineNumbr=$(echo "$charsetLines" | awk '/'$charset'/{print NR; exit}')
        sed -i "/$charset/ s/applyto\=()/applyto\=($lineNumbr)/" ./$1/$3 # Double quotes are critical here due to variable
    done
}

update_setsblock_after_partitionfinding()
#   This function splits a NEXUS file into individual blocks.
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of file with best models ($bestModls)
#         $3: name of file containing the extracted SETS-block ($setsBlock)
#   OUP:  file with a SETS-block
{
    # INTERNAL FUNCTION CHECKS
    (($# == 3)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    # Foo bar baz
    
}

########################################################################
########################################################################

# FUNCTIONS SPECIFIC TO 'JMODELTEST'

extract_modelinfo_from_jmodeltest()
#   This function extracts modelinfo from the output of jModeltest; the output was saved into logfiles ending with the name ".bestModel"
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of file to collect bestfit model per partition ($bestModls)
#         $3: boolean variable if verbose or not ($verboseBOOL)
#   OUP:  writes output to model overview file
{
    # INTERNAL FUNCTION CHECKS
    (($# == 3)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    count=$(ls -1 ./$1/*.bestModel 2>/dev/null | wc -l)
    if [ $count != 0 ]; then
        for file in ./$1/*.bestModel; do 
            echo -ne "$(basename $file)" | sed 's/partition_//g' | sed 's/\.bestModel//g' >> ./$1/$2
            bestModel=$(cat "$file" | grep -A1 ' Model selected:' | tail -n1 | sed -n 's/.*Model \= \([^ ]*\).*/\1/p' 2>/dev/null) # Parse best model from jModeltest output
            if [ ! -z "$bestModel" ]; then
                echo " $bestModel" >> ./$1/$2  # NOTE: model has to be preceeded by one space!
            else
                echo " GTR+I+G" >> ./$1/$2  # If error in modeltesting or parsing, set GTR+I+G as default model
                if [ $3 -eq 1 ]; then
                    echo -ne " WARN  | $(get_current_time) | No model extracted from file $file; setting model GTR+I+G as replacement.\n"
                fi
            fi
        done
    else
        echo -ne " ERROR | $(get_current_time) | No result files of the modeltesting (*.bestModel) found.\n"
        exit 1
    fi
}

modeltesting_via_jmodeltest()
#   This function conducts modeltesting via jModeltest for a series of input files; these input files start with the name "partition_"
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of jModeltest binary ($BinMDLTST)
#         $3: name of config file ($reformCFG)
#         $4: boolean variable if verbose or not ($verboseBOOL)
#   OUP:  none; generates *.bestModel* output files in temp folder
{
    # INTERNAL FUNCTION CHECKS
    (($# == 4)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done

    # USING CONFIG TEMPLATE
    CMDline=$(grep -A1 --ignore-case '^%JMODELTEST:' ./$1/$3 | tail -n1)
    CMDline=${CMDline//\[PATH_TO_JMODELTEST_JAR\]/$2} # Substitution with Bash's built-in parameter expansion
    CMDline=$(eval echo $CMDline)
    # MODELTESTING
    count=$(ls -1 ./$1/partition_* 2>/dev/null | wc -l)
    if [ $count != 0 ]; then
        for partit in ./$1/partition_*; do
        partit_RUNTIME_start=$(date +%s)
        coreCMD=${CMDline//\[PARTITION_NAME\]/$partit} # Substitution with Bash's built-in parameter expansion; # NOTE: Don't overwrite the variable $CMDline to perform different substitutions in each loop, instead save it as a new variable ($coreCMD)
        eval "$coreCMD 1>${partit}.bestModel 2>&1" # Executin of main_cmd
        partit_RUNTIME_dur=$(bc -l <<< "($(date +%s)-$partit_RUNTIME_start)/60")
        LC_ALL=C partit_RUNTIME_dur_pp=$(printf "%.3f minutes\n" $partit_RUNTIME_dur)
        if [ $4 -eq 1 ]; then
            echo -ne " INFO  | $(get_current_time) |   Processing complete for partition: $(basename $partit); Execution time: $partit_RUNTIME_dur_pp\n"
        fi
        done
    else
        echo -ne " ERROR | $(get_current_time) | No partition files (partition_*) found.\n"
        exit 1
    fi
}

########################################################################
########################################################################

# FUNCTIONS SPECIFIC TO 'SMS'

extract_modelinfo_from_sms()
#   This function extracts modelinfo from the output of sms; the output was saved into a file called "sms.csv" (default behaviour of SMS)
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of file to collect bestfit model per partition ($bestModls)
#         $3: boolean variable if verbose or not ($verboseBOOL)
#   OUP:  writes output to model overview file
{
    # INTERNAL FUNCTION CHECKS
    (($# == 3)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    count=$(ls -1 ./$1/*_sms.csv 2>/dev/null | wc -l)
    if [ $count != 0 ]; then
        for file in ./$1/*_sms.csv; do 
            echo -ne "$(basename $file)" | sed 's/partition_//g' | sed 's/\_sms\.csv//g' >> ./$1/$2
            bestModel=$(cat "$file" | grep -A1 'Model;Decoration' | tail -n1 | awk -F';' '{print $1$2}' 2>/dev/null) # Parse best model from SMS output
            if [ ! -z "$bestModel" ]; then
                echo " $bestModel" >> ./$1/$2  # NOTE: model has to be preceeded by one space!
            else
                echo " GTR+I+G" >> ./$1/$2  # If error in modeltesting or parsing, set GTR+I+G as default model
                if [ $3 -eq 1 ]; then
                    echo -ne " WARN  | $(get_current_time) | No model extracted from file $file; setting model GTR+I+G as replacement.\n"
                fi
            fi
        done
    else
        echo -ne " ERROR | $(get_current_time) | No result files of the modeltesting (*.bestModel) found.\n"
        exit 1
    fi
}

modeltesting_via_sms()
#   This function conducts modeltesting via SMS for a series of input files; these input files start with the name "partition_"
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of SMS binary ($BinMDLTST)
#         $3: name of config file ($reformCFG)
#         $4: boolean variable if verbose or not ($verboseBOOL)
#   OUP:  none; generates *.bestModel* output files in temp folder
{
    # INTERNAL FUNCTION CHECKS
    (($# == 4)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done

    # USING CONFIG TEMPLATE
    CMDline=$(grep -A1 --ignore-case '^%SMS:' ./$1/$3 | tail -n1)
    CMDline=${CMDline//\[PATH_TO_SMS_SHELLSCRIPT\]/$2} # Substitution with Bash's built-in parameter expansion
    CMDline=$(eval echo $CMDline)
    # MODELTESTING
    count=$(ls -1 ./$1/partition_*.phy 2>/dev/null | wc -l)
    if [ $count != 0 ]; then
        for partit in ./$1/partition_*.phy; do
        partit_RUNTIME_start=$(date +%s)
        coreCMD=${CMDline//\[PARTITION_NAME\]/$partit} # Substitution with Bash's built-in parameter expansion; # NOTE: Don't overwrite the variable $CMDline to perform different substitutions in each loop, instead save it as a new variable ($coreCMD)
        coreCMD=${coreCMD//\[OUTPUT_FILE\]/${partit%.phy*}_sms.csv} # Substitution with Bash's built-in parameter expansion
        eval "$coreCMD 1>${partit%.phy*}.runlog 2>&1" # Executin of main_cmd
        partit_RUNTIME_dur=$(bc -l <<< "($(date +%s)-$partit_RUNTIME_start)/60")
        LC_ALL=C partit_RUNTIME_dur_pp=$(printf "%.3f minutes\n" $partit_RUNTIME_dur)
        if [ $4 -eq 1 ]; then
            echo -ne " INFO  | $(get_current_time) |   Processing complete for partition: $(basename $partit); Execution time: $partit_RUNTIME_dur_pp\n"
        fi
        done
    else
        echo -ne " ERROR | $(get_current_time) | No partition files (partition_*) found.\n"
        exit 1
    fi
}

########################################################################
########################################################################

# FUNCTIONS SPECIFIC TO 'PARTITIONFINDER'

# assemble_mrbayes_block_from_partitionfinder_results()
# #   This function ...
# #   INP:  $1: path to temp folder ($tmpFOLDER)
# #         $2: name of outfile ($mbOUTFILE)
# #   OUP:  append to the outfile
# {
#     # INTERNAL FUNCTION CHECKS
#     (($# == 2)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
#     for ((i=1; i<=$#; i++)); do
#         argVal="${!i}"
#         [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
#     done
#     
#     pf_bestscheme=./$1/analysis/best_scheme.txt
#     kw1="begin mrbayes;"
#     kw2="end;"
#     mrbayes_block=$(sed -n "/$kw1/,/$kw2/p" $pf_bestscheme)
#     if [ ! -z "$mrbayes_block" ]; then
#         echo "$mrbayes_block" >> $2 # NOTE: Append only! Also: $2 (i.e., mbOUTFILE) does not reside in $1 (i.e., $tmpFOLDER)
#     else
#         echo -ne " ERROR | $(get_current_time) | Parsing of MRBAYES-block unsuccessful from file: $pf_bestscheme\n"
#         exit 1
#     fi
# }

generate_setsblock_from_partitionfinder_results()
#   This function extracts the new charset info (inlcuding the best
#   partitioning scheme).
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of outfile ($nwSetsBlk)
#   OUP:  write to the outfile
{

    # INTERNAL FUNCTION CHECKS
    (($# == 2)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done

    pf_bestscheme=./$1/analysis/best_scheme.txt

    if [ -f "$pf_bestscheme" ]; then
        # EXTRACT PARTITION SCHEME AND CHARSETS
        kw1="Scheme Description in PartitionFinder format"
        kw2="begin sets;"
        kw3="end;"
        region_of_interest=$(sed -n "/$kw1/,/$kw3/p; /$kw3/q" $pf_bestscheme)
        best_scheme=$(echo "$region_of_interest" | grep -A1 "$kw1" | tail -n1 | awk -F"=" '{print $2}')
        new_charsetLines=$(echo "$region_of_interest" | sed -n "/$kw2/,/$kw3/p" | grep --ignore-case "charset")

        # ADD BEST_SCHEME INFO TO CHARSET LINES
        best_scheme=$(echo "${best_scheme//, /,}")
        best_scheme=$(echo "${best_scheme//(/[}")
        best_scheme=$(echo "${best_scheme//)/]}")
        best_scheme=$(echo "${best_scheme//;/}" | sed -e 's/^[ \t]*//')
        adjusted_charsetLines=$(awk 'FNR==NR{split($0,strarr);nextfile}/Subset/{print $0,strarr[++i];next}1' <(echo "$best_scheme") <(echo "$new_charsetLines"))
        echo -ne "begin sets;\n$adjusted_charsetLines\nend;" | awk '{$1=$1;print}' > ./$1/$2

    else
        echo -ne " ERROR | $(get_current_time) | No result files of the modeltesting (*.bestModel) found.\n"
        exit 1
    fi
}

extract_modelinfo_from_partitionfinder()
#   This function ...
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of file to collect bestfit model per partition ($bestModls)
#   OUP:  writes the bestModls file to disk
{
    # INTERNAL FUNCTION CHECKS
    (($# == 2)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    pf_bestscheme=./$1/analysis/best_scheme.txt
    if [ -f "$pf_bestscheme" ]; then
        kw1="Subset \| Best Model"
        kw2="Scheme Description in PartitionFinder format"
        bestMdlOvw=$(sed -n "/$kw1/,/$kw2/p" $pf_bestscheme | grep '^[0-9]')
        bestModels=$(echo "$bestMdlOvw" | sed 's/[ \t]*//g' | awk -F'|' '{print $5" "$2}')
        if [ ! -z "$bestModels" ]; then
            echo "$bestModels" > ./$1/$2 # It's fine to overwrite the file here, as variable $bestModels already contains model names
        else
            echo -ne " WARN  | $(get_current_time) | Parsing of models unsuccessful from file: $pf_bestscheme\n"
        fi
    else
        echo -ne " ERROR | $(get_current_time) | No result files of the modeltesting (*.bestModel) found.\n"
        exit 1
    fi
}

modeltesting_via_partitionfinder()
#   This function conducts partitionfinding / modeltesting via PartitionFinder
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: path to PartitionFinder Python script ($BinMDLTST)
#         $3: name of config file ($reformCFG)
#   OUP:  none; generates an output folder named 'analysis' in temp folder
{
    # INTERNAL FUNCTION CHECKS
    (($# == 3)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    # Test if Python2.7 present
    if command -v python2.7 1>/dev/null 2>&1; then
        :
    else
        echo -ne " ERROR | $(get_current_time) | Cannot find Python2.7 interpreter.\n"
        exit 1
    fi
    
    # Conduct partitionfinding / modeltesting
    if [ -f "./$1/partition_finder.cfg" ]; then
        # USING CONFIG TEMPLATE
        CMDline=$(grep -A1 --ignore-case '^%PARTITIONFINDER_CMDLINE:' ./$1/$3 | tail -n1)
        CMDline=${CMDline//\[PATH_TO_PARTITIONFINDER_PY\]/$2} # Substitution with Bash's built-in parameter expansion
        coreCMD=${CMDline//\[INPUT_FOLDER\]/$1}
        eval "$coreCMD 1>./$1/partitionfinder_run.log 2>&1" # Executin of main_cmd
    else
        echo -ne " ERROR | $(get_current_time) | No PartitionFinder config file (partition_finder.cfg) found.\n"
        exit 1
    fi
}

write_partitionfinder_config_file()
#   This function generates a config file as required by PartitionFinder.
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of config file ($reformCFG)
#         $3: name of phylip-formatted file ($phylipFil)
#         $4: name of file containing the extracted SETS-block ($setsBlock)
#         $5: boolean variable if userscheme only or not ($usrschmBOOL)
#   OUP:  writes a phylip-formatted file to disk
{
    # INTERNAL FUNCTION CHECKS
    (($# == 5)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    charsetLines=$(cat ./$1/$4 | grep 'charset')

    # USING CONFIG TEMPLATE
    CMDline=$(grep -A1 --ignore-case '^%PARTITIONFINDER_CFG:' ./$1/$2 | tail -n1)
    CMDline=${CMDline//\[NAME_OF_ALIGNMENT\]/$3} # Substitution with Bash's built-in parameter expansion
    CMDline=${CMDline//\[LIST_OF_DATA_BLOCKS\]/$charsetLines}

    # Setting userscheme-only search
    if [ $5 -eq 1 ]; then
        echo -ne " INFO  | $(get_current_time) | Estimating model fit of user-defined partition scheme only\n"
        CMDline=$(echo "$CMDline" | sed 's/\[schemes\].*/[schemes]/') # Remove everything after keyword "[schemes]"
        CMDline+="\nsearch=user;" # Appending string to variable
        charsetUserscheme=$(echo "$charsetLines" | awk '{print "("$2")"}' | tr -d '\n') # NOTE: tr-command removes newlines from list
        CMDline+="\nuserdefined=$charsetUserscheme;" # Appending string to variable
    fi

    # OUTPUT
    CMDline=$(echo "$CMDline" | awk '{$1=$1;print}') # NOTE: Remove all leading and trailing whitespaces
    echo -e "$CMDline" > ./$1/partition_finder.cfg
}

########################################################################
########################################################################

# FUNCTIONS SPECIFIC TO 'PARTITIONTEST'


extract_modelinfo_from_partitiontest()
#   This function ...
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of phylip-formatted file ($phylipFil)
#         $3: name of file to collect bestfit model per partition ($bestModls)
#   OUP:  writes the bestModls file to disk
{
    # INTERNAL FUNCTION CHECKS
    (($# == 3)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    pt_results=./$1/partest_$2/results
    if [ -f "$pt_results" ]; then
        best_scheme=$(sed -n '/\<name\>/,/\<\/name\>/p' $pt_results | grep -m1 -A1 "<name>" | tail -n1) # NOTE: "-m 1" in grep means return the first match
        modelinf_str=$(sed -n '/\<partition\>/,/\/partition/p' $pt_results | sed -n '/\<partition\>/,/<bestModel/p' | grep -Ev "<name>|</name>|</partition>")
        modelinf_str=$(echo "$modelinf_str" | sed -e 's/^[ \t]*//' | awk '/\<partition|\)/{printf "%s ", $0; next} 1')
    
        touch ./$1/$3
        while IFS= read -r LINE; do 
            partitionCounter=$(echo "$LINE" | sed -rn 's/.*id="([^"]*)".*/\1/p')
            partitionCONTENT=$(echo "$LINE" | sed -rn 's/.*\(([^)]*).*/\1/p')
            partitionModel=$(echo "$LINE" | sed -rn 's/.*bestModel name="([^"]*)".*/\1/p')
            echo "Subset$partitionCounter $partitionModel [$partitionCONTENT]" >> ./$1/$3
        done <<< "$modelinf_str" # Using a here-string
    else
        echo -ne " ERROR | $(get_current_time) | File $pt_results not found.\n"
        exit 1
    fi
}

modeltesting_via_partitiontest()
#   This function conducts partitionfinding / modeltesting via PartitionTest
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: path to ParTest ($BinMDLTST)
#         $3: name of config file ($reformCFG)
#         $4: name of phylip-formatted file ($phylipFil)
#   OUP:  none; generates an output folder named 'analysis' in temp folder
{
    # INTERNAL FUNCTION CHECKS
    (($# == 4)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    # Conduct partitionfinding / modeltesting
    if [ -f "./$1/partition_test.cfg" ]; then
        # USING CONFIG TEMPLATE
        CMDline=$(grep -A1 --ignore-case '^%PARTITIONTEST_CMDLINE:' ./$1/$3 | tail -n1)
        CMDline=${CMDline//\[PATH_TO_PARTEST\]/$2} # Substitution with Bash's built-in parameter expansion
        CMDline=${CMDline//\[NAME_OF_ALIGNMENT\]/.\/$1\/$4}
        coreCMD=${CMDline//\[NAME_OF_CFG_FILE\]/.\/$1\/partition_test.cfg}
        eval "$coreCMD 1>./$1/partition_test.log 2>&1" # Executin of main_cmd
    else
        echo -ne " ERROR | $(get_current_time) | No PartitionFinder config file (partition_finder.cfg) found.\n"
        exit 1
    fi
    
    # Adjusting for current bug in partitiontest (output not saved to path specified in config file)
    mv partest_$4 ./$1 # Moving outfile to tmpFolder
}

write_partitiontest_config_file()
#   This function generates a config file as required by PartitionFinder.
#   INP:  $1: path to temp folder ($tmpFOLDER)
#         $2: name of config file ($reformCFG)
#         $3: name of phylip-formatted file ($phylipFil)
#         $4: name of file containing the extracted SETS-block ($setsBlock)
#         $5: boolean variable if userscheme only or not ($usrschmBOOL)
#   OUP:  writes a config file for partitiontest to disk
{
    # INTERNAL FUNCTION CHECKS
    (($# == 5)) || { printf " ERROR | $(get_current_time) | The following function received an incorrect number of arguments: ${FUNCNAME[0]}\n"; exit 1; }
    for ((i=1; i<=$#; i++)); do
        argVal="${!i}"
        [[ -z "${argVal// }" ]] && { printf " ERROR | $(get_current_time) | The following function received an empty input argument: ${FUNCNAME[0]}\n"; exit 2; }
    done
    
    charsetLines=$(cat ./$1/$4 | grep 'charset')

    # USING CONFIG TEMPLATE
    CMDline=$(grep -A1 --ignore-case '^%PARTITIONTEST_CFG:' ./$1/$2 | tail -n1)
    charsetLines=$(echo "$charsetLines" | sed "s/charset //" | sed "s/\;//")
    CMDline=${CMDline//\[OUT_PATH\]/.\/$1\/} # Substitution with Bash's built-in parameter expansion
    CMDline=${CMDline//\[LIST_OF_DATA_BLOCKS\]/$charsetLines}

    # Setting userscheme-only search
    if [ $5 -eq 1 ]; then
        echo -ne " INFO  | $(get_current_time) | Estimating model fit of user-defined partition scheme only\n"
        CMDline=$(echo "$CMDline" | sed 's/\[schemes\].*/[schemes]/') # Remove everything after keyword "[schemes]"
        CMDline+="\nsearch=user;" # Appending string to variable
        charsetUserscheme=$(echo "$charsetLines" | awk '{print "("$2")"}' | tr -d '\n') # NOTE: tr-command removes newlines from list
        CMDline+="\nuserdefined=$charsetUserscheme;" # Appending string to variable
    fi

    # OUTPUT
    CMDline=$(echo "$CMDline" | awk '{$1=$1;print}') # NOTE: Remove all leading and trailing whitespaces
    echo -e "$CMDline" > ./$1/partition_test.cfg
}

########################################################################
########################################################################

## EVALUATING SYSTEM, BASH SHELL AND SCRIPT EXECUTION
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Evaluating system, bash shell and script execution"\\n
fi

# Print system details to log
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) |   System info: $(uname -sr 2>/dev/null), proc: $(uname -p 2>/dev/null), arch: $(uname -m 2>/dev/null), numcores: $(get_num_of_avail_cores)"\\n
    echo -ne " INFO  | $(get_current_time) |   Bash info: $(bash --version | head -n1 2>/dev/null)"\\n
fi

# Print all bash arguments used to start this script
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) |   Command used: $THIS_SCRIPT $(echo $@)"\\n
fi

########################################################################

## CHECKING INFILES
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Checking infiles\n"
fi

# Renaming input variables
nexINFILE=$OPT_A
cfgINFILE=$OPT_B
typMDLTST=$OPT_C
BinMDLTST=$OPT_D
mbOUTFILE=$OPT_E

if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) |   Type of Modeltesting selected: $typMDLTST\n"
fi

# Define runfile namestem
baseName=$(basename $nexINFILE) # Using basename to strip off path
filenStem=${baseName%.nex*} # Using parameter expansion to remove file extension

# Define outfile names
reformNEX=${filenStem}_ReformNEXFile
reformCFG=${filenStem}_ReformCFGFile
dataBlock=${filenStem}_NexusDatBlock
setsBlock=${filenStem}_NexusSetBlock
bestModls=${filenStem}_BestFitModels
lsetDefns=${filenStem}_LsetDefinitns
phylipFil=${filenStem}_PhylipFormatd # Bash string extension cannot handle dots (i.e., must be "myfile_phy" instead of "myfile.phy")
nwSetsBlk=${filenStem}_NewCharsetLns
newNexFil=${mbOUTFILE}_new.nex

# Checking input and output file availability
check_inp_outp_availability $nexINFILE $cfgINFILE $BinMDLTST $mbOUTFILE $get_current_time

# Make temporary folder
#tmpFOLDER=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32)
if [ \( "$typMDLTST" = "partitionfinder" -a "$usrschmBOOL" -eq 1 \) -o \( "$typMDLTST" = "partitiontest" -a "$usrschmBOOL" -eq 1 \) ]; then
    tmpFOLDER=${filenStem}_${typMDLTST}_userscheme_${RUNTIME_start_pp}_runFiles
else
    tmpFOLDER=${filenStem}_${typMDLTST}_${RUNTIME_start_pp}_runFiles
fi
mkdir -p $tmpFOLDER

########################################################################

## RE-FORMATTING INPUT NEXUS FILE
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Re-formatting input NEXUS file\n"
fi

reformat_nexus_file $nexINFILE $tmpFOLDER/$reformNEX
reformat_config_file $cfgINFILE $typMDLTST $tmpFOLDER/$reformCFG

# Extract number of characters in DNA matrix
ncharVar=$(grep ^dimensions $tmpFOLDER/$reformNEX | sed -n 's/.*nchar=\([^;]*\).*/\1/p') # NOTE: Terminating the search for ntax=xx with a semi-colon means that nchar has to come as last attribute (i.e., after ntax) in dimensions line.

########################################################################

## SPLITTING NEXUS FILE INTO BLOCKS
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Splitting NEXUS file into blocks\n"
fi

split_nexus_into_blocks $tmpFOLDER $reformNEX $dataBlock $setsBlock

########################################################################

## CONFIRMING THAT PARTITIONS DO NOT OVERLAP
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Confirming that partitions do not overlap\n"
fi

test_if_partitions_overlap $tmpFOLDER $setsBlock

########################################################################

## ENSURING THAT PARTITIONS FORM A CONTINUOUS RANGE
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Ensuring that partitions form a continuous range\n"
fi

ensure_partitions_form_continuous_range $tmpFOLDER $setsBlock $ncharVar

########################################################################

## SPLITTING MATRIX INTO PARTITIONS
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Splitting matrix into partitions\n"
fi

split_matrix_into_partitions $tmpFOLDER $dataBlock $setsBlock "original"

########################################################################

## PREPARING FILES FOR PARTITIONFINDING / MODELTESTING
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Preparing files for partitionfinding / modeltesting\n"
fi

if [ "$typMDLTST" = "sms" ]; then
    for partit in ./$tmpFOLDER/partition_*; do
        partit_ncharVar=$(grep ^dimensions $partit | sed -n 's/.*nchar=\([^;]*\).*/\1/p') # Extract number of characters in partition
        partit_name=$(basename $partit) # Because convert_datablock_to_phylip() concatenates path and filename, I need to extract basename of infile here
        convert_datablock_to_phylip $tmpFOLDER $reformNEX $partit_name $partit_ncharVar ${partit_name}.phy
    done
fi

if [ "$typMDLTST" = "partitionfinder" ]; then
    convert_datablock_to_phylip $tmpFOLDER $reformNEX $dataBlock $ncharVar $phylipFil
    write_partitionfinder_config_file $tmpFOLDER $reformCFG $phylipFil $setsBlock $usrschmBOOL
elif [ "$typMDLTST" = "partitiontest" ]; then
    convert_datablock_to_phylip $tmpFOLDER $reformNEX $dataBlock $ncharVar $phylipFil
    write_partitiontest_config_file $tmpFOLDER $reformCFG $phylipFil $setsBlock $usrschmBOOL
fi

########################################################################

## CONDUCTING PARTITIONFINDING / MODELTESTING
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Conducting partitionfinding / modeltesting via: $typMDLTST\n"
fi

if [ "$typMDLTST" = "jmodeltest" ]; then
    modeltesting_via_jmodeltest $tmpFOLDER $BinMDLTST $reformCFG $verboseBOOL
elif [ "$typMDLTST" = "sms" ]; then
    modeltesting_via_sms $tmpFOLDER $BinMDLTST $reformCFG $verboseBOOL
elif [ "$typMDLTST" = "partitionfinder" ]; then
    modeltesting_via_partitionfinder $tmpFOLDER $BinMDLTST $reformCFG
elif [ "$typMDLTST" = "partitiontest" ]; then
    modeltesting_via_partitiontest $tmpFOLDER $BinMDLTST $reformCFG $phylipFil
fi

########################################################################

## EXTRACTING INFORMATION FROM PARTITIONFINDING / MODELTESTING RESULTS
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Extracting information from partitionfinding / modeltesting results\n"
fi

if [ "$typMDLTST" = "jmodeltest" ]; then
    extract_modelinfo_from_jmodeltest $tmpFOLDER $bestModls $verboseBOOL
    convert_models_into_lset $tmpFOLDER $bestModls $lsetDefns $setsBlock
elif [ "$typMDLTST" = "sms" ]; then
    extract_modelinfo_from_sms $tmpFOLDER $bestModls $verboseBOOL
    convert_models_into_lset $tmpFOLDER $bestModls $lsetDefns $setsBlock
elif [ "$typMDLTST" = "partitiontest" ]; then
    extract_modelinfo_from_partitiontest $tmpFOLDER $phylipFil $bestModls
    convert_models_into_lset $tmpFOLDER $bestModls $lsetDefns $setsBlock
elif [ "$typMDLTST" = "partitionfinder" ]; then
    extract_modelinfo_from_partitionfinder $tmpFOLDER $bestModls
    # No need to convert models into lset for partitionfinder; already done by this software
fi

########################################################################

## UPDATING SETS-BLOCK

if [ \( "$typMDLTST" = "partitionfinder" -a "$usrschmBOOL" -eq 0 \) -o \( "$typMDLTST" = "partitiontest" -a "$usrschmBOOL" -eq 0 \) ]; then

    if [ $verboseBOOL -eq 1 ]; then
        echo -ne " INFO  | $(get_current_time) | Updating SETS-block\n"
    fi

    if [ "$typMDLTST" = "partitionfinder" ]; then
        generate_setsblock_from_partitionfinder_results $tmpFOLDER $nwSetsBlk
    elif [ "$typMDLTST" = "partitiontest" ]; then
        #generate_setsblock_from_partitiontest_results $tmpFOLDER $nwSetsBlk
        echo "Function Missing!"
        exit 1
    fi

    split_matrix_into_partitions $tmpFOLDER $dataBlock $nwSetsBlk "new"
    if [ $verboseBOOL -eq 1 ]; then
        echo -ne " INFO  | $(get_current_time) | Assembling new NEXUS file with optimal partitions\n"
    fi
    
    assemble_new_nexus_from_new_partitions $tmpFOLDER $dataBlock "new" $newNexFil

fi

########################################################################

## ASSEMBLING OUTPUT FILE
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Assembling output file\n"
fi

echo -e "#NEXUS\n" > $mbOUTFILE

# Reconstitute DATA-block as interleaved
if [ \( "$typMDLTST" = "partitionfinder" \) -o \( "$typMDLTST" = "partitiontest" \) ]; then
    reconstitute_datablock_as_interleaved $tmpFOLDER $dataBlock $mbOUTFILE "new"
else
    reconstitute_datablock_as_interleaved $tmpFOLDER $dataBlock $mbOUTFILE "original"
fi

# Append the SETS-block, which is commented out
echo -e "\n[\n$(cat $tmpFOLDER/$setsBlock)\n]\n" >> $mbOUTFILE

# Append info on best-fitting models
echo -e "\n[\nBest-fitting models identified:\n$(cat $tmpFOLDER/$bestModls)\n]\n" >> $mbOUTFILE

if [ \( "$typMDLTST" = "partitionfinder" \) -o \( "$typMDLTST" = "partitiontest" \) ]; then
    #assemble_mrbayes_block_from_partitionfinder_results $tmpFOLDER $mbOUTFILE
    
    # REPLACE WITH A FUNCTION THAT MATCHES THE SUBSET NAMES WITH THE PARTITIONS IN temp_NewCharsetLns
    echo "Function Missing!"
    exit 1
else
    assemble_mrbayes_block_general $tmpFOLDER $mbOUTFILE $lsetDefns $setsBlock $reformCFG
fi

########################################################################

## CLEANING UP THE WORK DIRECTORY
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Cleaning up\n"
fi

if [ $keepflsBOOL -eq 0 ]; then
    rm -r $tmpFOLDER
fi

# Stop timing execution time
RUNTIME_dur=$(bc -l <<< "($(date +%s)-$RUNTIME_start)/60")
LC_ALL=C RUNTIME_dur_pp=$(printf "%.3f minutes\n" $RUNTIME_dur)  # NOTE: "LC_ALL=C" is important due to different locales (German comma vs. world's decimal point)

# End of file message
if [ $verboseBOOL -eq 1 ]; then
    echo -ne " INFO  | $(get_current_time) | Processing complete for file: $nexINFILE; Execution time: $RUNTIME_dur_pp\n"
fi

########################################################################

## EXIT WITHOUT MISTAKES
exit 0

########################################################################