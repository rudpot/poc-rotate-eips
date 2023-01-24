#!/bin/bash

# Every time the script is called see if a multiple of x minutes has passed and associate new IPs
ROTATION_FREQENCY=3

# Modulo function to pick from array
#
# Inputs
#
#   index in array - modulo will loop to beginning if number bigger than array length
#   array of entries to pick from - can be passed a space separated string or multiple parameters
#
# Output
#
#   sets global variable $result
#
get_array_entry_into_result_by_modulo() {
    local my_index=$1
    shift
    local my_array=($@)
    local my_array_len=${#my_array[@]}

    result=${my_array[$(($my_index % $my_array_len))]}
}

# Select array entry based on time of day
#
# Inputs
#
#   rotation time in minutes - used in modulo
#   rotation index offset - use this if you have more than one VM you are rotating
#   array of entries to pick from - can be passed a space separated string or multiple parameters
#
# Output
#
#   sets global variable $result
#
# 
get_array_entry_into_result_by_time() {
    local rotation_minutes=$1
    shift
    local rotation_offset=$1
    shift
    local my_array=($@)
    local my_array_len=${#my_array[@]}
    local my_index=$(( ( ( $(date '+%s') / (${rotation_minutes}*60) ) + $rotation_offset + $my_array_len) % $my_array_len ))

    result=${my_array[$(($my_index % $my_array_len))]}
}


# Get a list of IPs we can draw from
SORTED_IP_ALLOCATIONS=$( aws ec2 describe-addresses \
  --filters Name=tag:Group,Values=EipRotatePocEip \
| jq -rc '.Addresses[] | [ ( .Tags[] | select(.Key == "Name").Value ), .AllocationId ]' \
| sort \
| sed 's/^.*,"//; s/".*$//' )
echo "Avaliable EIP allocations ${SORTED_IP_ALLOCATIONS}"

# # Example how to select entry from array with modulo
# get_array_entry_into_result_by_modulo 3 $SORTED_IP_ALLOCATIONS
# echo $result

# # Example how to select entry from array based on time of day
# # and rotation time in minutes
# get_array_entry_into_result_by_time 3 0 $SORTED_IP_ALLOCATIONS
# echo $result

# Get a list of Instances we want to rotate IPs for
SORTED_INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters Name=tag:Group,Values=EipRotatePocInstance \
| jq -rc '.Reservations[].Instances[] | [ ( .Tags[] | select(.Key == "Name").Value ), .InstanceId ]' \
| sort \
| sed 's/^.*,"//; s/".*$//' )

offset=0
for instance in $SORTED_INSTANCE_IDS; do

    # Remove the old address and get auto-assigned non-EIP (paranoid)

    ASSOCIATION_ID=$( aws ec2 describe-addresses \
        --filters \
            Name=instance-id,Values=${instance} \
            Name=tag:Group,Values=EipRotatePocEip \
        --query Addresses[0].AssociationId \
        --output text )

    if [[ -n "$ASSOCIATION_ID" && "$ASSOCIATION_ID" != "None" ]]; then
        echo "Disassociating ${ASSOCIATION_ID} from instance ${offset} id ${instance}"
        aws ec2 disassociate-address --association-id ${ASSOCIATION_ID}
    else
        echo "Instance ${offset} id ${instance} does not have an EIP associated"
    fi

    # Associate a new IP

    # Get a new IP every 3 minutes
    get_array_entry_into_result_by_time $ROTATION_FREQENCY $offset $SORTED_IP_ALLOCATIONS
    ALLOCATION_ID=$result

    echo "Associating instance ${offset} id ${instance} with ${ALLOCATION_ID}"
    aws ec2 associate-address \
        --allocation-id=${ALLOCATION_ID} \
        --instance-id=${instance}

    # Count backwards ... ?
    offset=$(($offset+1))
done