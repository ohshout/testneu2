#!/bin/bash
#Usage with help
set -e
usage() { 
    cat <<- EOF
    
    usage: `basename $0` [-ojt] <config_file> 

    Script determines passing hours for any clusters, as definied by <config file>.
    <config file> is required to run this script.

    OPTIONS:
        -o          Determines if the cluster is online or not
        -j          Determines which sw branch for a given cluster
        -t          Prints the time window where passing hours are counted
        -h          shows help
        -ojt        All options (or any subset) can be run at the same time
    
EOF
    exit 0;
}

#shw_sts=""
#shw_jenk=""
## Print usage if no arguments provided

if [ ${#@} == 0 ]; then
    usage
fi

#OPTIND=1
#get_out=0
##Parse arguements and parameters
if [ ! -s $1 ]; then 
    #local OPTIND
    while [ ! -e $1 ]; do
        #echo $1
        #echo "still in while loop for $1"
        while getopts "ojt:h" opt; do
            #echo "Starting case compare of $1..."
            case "$opt" in
                h)
                    usage
                    ;;
                o)
                    shw_sts="1"
                    ;;
                j)
                    shw_jenk="1"
                    ;;
                t)
                    shw_time="1"
                    ;;
                *)
                    usage
                    echo "Invalid option: $OPTARG requires an argument" 1>&2
                    exit 0
                    ;;
            esac
        done
        #shift $((OPTIND -1))
#        echo "OPTIND = $OPTIND"
        shift
#        echo "This is inside case: $1"
        cfg_file=$1
        
    done
#    echo "exectuing: $cfg_file"
    else
        cfg_file=$1
#        echo "exectuing: $cfg_file"
    fi
#echo "shw_sts = $shw_sts"
#echo "shw_jenk = $shw_jenk"

#echo $get_out

#if [ $get_out -eq 1 ]; then
#echo "Stop here!"
#    exit 1
#fi

#echo "Show on_offline status:$shw_sts"
#echo "Show jenkins branch:$shw_jenk"
     
#if [ "$1" == "-h" -o "$1" == "--help" ]; then
#	echo "Usage: `basename $0` [-h] config_file"
#	exit 0
#fi

#cfg_file=$1

#echo $cfg_file
## Check if config file exists
TODAY=$(date)
echo -e "\n-----------------------------------------------------"
echo "Date: $TODAY"
echo "-----------------------------------------------------"

if [ -e "$cfg_file" ]; then
    echo -e "\nProcessing Configuration $cfg_file........\n"
else 
    echo -e "\nConfiguration file $cfg_file does not exist\nPlease use a valid configuraiton file!\n"
    exit 1
fi 

## Create array from configuration file
readarray -t arr < $cfg_file
declare -a arr="($(<$cfg_file))"

## Config Info
dev_type=${arr[1]}
dev_desc=${arr[3]}

## Create arrays
bld_hrs=()
bld_cnt=()

echo -e "Calculating $dev_desc Passing Hours...."
echo "------------------------------------------------------------------------------------------"
## Loop through array
for ((i=4,j=0;i<${#arr[@]};i+=4,++j))
do
#    echo ${arr[i]}
    if [ "$shw_time" ]; then
        ## Is DUT still running?
        strt_date="(Start date: ${arr[i+2]})"
        if [ "${arr[i+3]}" != "present" ]; then
            end_date="(End date: ${arr[i+3]})"
        else
            end_date="(still deployed)"
        fi
    else
        strt_date=""
        end_date=""
    fi

    if [ "$shw_jenk" ]; then
        tmp_jenk="($(PGPASSWORD=readonly psql -h ci-metrics-db2 -U readonly -d triage_tool -c "select jenkins.name from
            jenkins, jenkins_nodes
            where jenkins_nodes.name='${arr[i]}' || '-lp' and jenkins_nodes.jenkins_id = jenkins.id
            ORDER BY (jenkins_nodes.updated_at) DESC
            LIMIT 1;"))"
	jenk=$(grep -o -E '\w+.+-irjenkins' <<< "$tmp_jenk" | cat)
	##Check if output is null
	if [ -z $jenk ]; then
        jenk=$(echo "No jenkins assigned yet!")
        fi

    else
        jenk=""
    fi

    ##Set cluster status
    if [ "$shw_sts" ]; then
        tmp_sts="($(PGPASSWORD=readonly psql -h ci-metrics-db2 -U readonly -d triage_tool -c "select status from
            jenkins_nodes, runs 
            where runs.node='${arr[i]}' || '-lp' and jenkins_nodes.name = runs.node
            ORDER BY (jenkins_nodes.updated_at) DESC
	    LIMIT 1;"))"

	sts=$(grep -o -E '\w+line' <<< "$tmp_sts" | cat)
	## Check is output is null
	if [ -z $sts ]; then
	sts=$(echo offline)
	fi

    else
        sts=""
    fi

        ##PSQL query to database | grab floating point hours only
	    if [ "${arr[i+3]}" == "present" ]; then
            bld_hrs+=($(PGPASSWORD=readonly psql -h ci-metrics-db2 -U readonly -d triage_tool -c "select sum(duration / 3600) \"hours\" from
	        runs where runs.node='${arr[i]}' || '-lp' and runs.result = 'success' and runs.completed >= '${arr[i+2]}';" | grep -m1 -Eo '[+-]?[0-9]+([.][0-9]+)?'))
	    #sleep 0.5
        #echo -e "output of psql query" ${bld_hrs[j]}
        ##Convert blade hours from fp to int
        else 
            bld_hrs+=($(PGPASSWORD=readonly psql -h ci-metrics-db2 -U readonly -d triage_tool -c "select sum(duration / 3600) \"hours\" from
            runs where runs.node='${arr[i]}' || '-lp' and runs.result = 'success' and runs.completed >= '${arr[i+2]}' and runs.completed <= '${arr[i+3]}';" | grep -m1 -Eo '[+-]?[0-9]+([.][0-9]+)?'))
        fi
        bld_hrs[j]=$( printf "%.0f" ${bld_hrs[j]})
        
        ## Return of 1 means no valid testing hours.  Do not count.

        if [ ${bld_hrs[j]} -le "1" ]; then
            #echo "Testing has not started on ${arr[i]}."
            bld_hrs[j]="0"
            ##Blade hours * number of blades
            bld_cnt+=($(echo "${bld_hrs[j]} * ${arr[i+1]}" | bc))
	    echo -e "${arr[i]} $sts $jenk    \t:\t ${bld_hrs[j]} hours\t\t * ${arr[i+1]} $dev_type"s"\t = ${bld_cnt[j]} hours\t(Waiting for Deployment)"
	    #echo -e "${arr[i]} $sts $jenk\t:\t ${bld_hrs[j]} hours\t\t * ${arr[i+1]} $dev_type"s"\t = ${bld_cnt[j]} hours\t(Waiting for Deployment)"
        else
         
          ##Blade hours * number of blades
            bld_cnt+=($(echo "${bld_hrs[j]} * ${arr[i+1]}" | bc))
          ##Print result per array entry
            BLD_HR_LEN=$(echo -n ${bld_hrs[j]} | wc -m)

          ##Format output
            if [ $BLD_HR_LEN -lt "4" ]; then
		echo -e "${arr[i]} $sts $jenk    \t:\t ${bld_hrs[j]} hours\t\t * ${arr[i+1]} $dev_type"s"\t = ${bld_cnt[j]} hours\t$strt_date \t$end_date"
        	#echo -e "${arr[i]} $sts $jenk\t:\t ${bld_hrs[j]} hours\t\t * ${arr[i+1]} $dev_type"s"\t = ${bld_cnt[j]} hours\t$strt_date\t$end_date"
            else
        	echo -e "${arr[i]} $sts $jenk    \t:\t ${bld_hrs[j]} hours\t\t * ${arr[i+1]} $dev_type"s"\t = ${bld_cnt[j]} hours\t$strt_date\t$end_date" 
		#echo -e "${arr[i]} $sts $jenk\t:\t ${bld_hrs[j]} hours\t\t * ${arr[i+1]} $dev_type"s"\t = ${bld_cnt[j]} hours\t$strt_date\t$end_date"            
            fi
        fi
done

		##Print total hours
tot=0
for i in ${bld_cnt[@]}; do
    tot=$(echo $tot + $i | bc -l);
done
tot=$( printf "%.0f" $tot )
echo "------------------------------------------------------------------------------------------"
echo -e "Total Passing Hours: $tot hours\n"
