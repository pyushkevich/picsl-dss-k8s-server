#!/bin/bash

# The services being handled by this script
SERVICE_NAMES=(ASHS-PMC)
SERVICE_VERSIONS=(".*")

# Continuous loop to check for tickets, claim them, and send to k8s cluster
function dss_service_loop()
{
# Type of server we are trying to run (prod/dev)
  deployment=${1?}

  # Get the number of maximum concurrent pods allowed
  max_pods=${2?}

  # Get a temp dir prefix
  TMPPREF=/tmp/${deployment}

  # Infinite loop
  while true; do

    # Get the current pods
    kubectl get pods > ${TMPPREF}_pods.txt

    if [[ $? -ne 0 ]]; then
      echo "$(date)   Pods listing failed"
      sleep 15
      continue
    fi

    # Count the number of pods currenly running
    n_pods=$(cat ${TMPPREF}_pods.txt | grep "ashs-worker" | awk '$3 == "Running" || $3 == "ContainerCreating" || $3 == "Pending" {print $1}' | wc -l | xargs)
    echo "$(date)   Currently $n_pods of $max_pods Pods are active"

    # If there is not space on the cluster, wait a little
    if [[ $n_pods -ge $max_pods ]]; then
      echo "$(date)   Maximum number of concurrent pods exceeded"
      sleep 15
      continue
    fi

    # Get a list of services we offer and select the subset handled on the cloud
    itksnap-wt -P -dssp-services-list > ${TMPPREF}_services.txt

    # Generate the list of all services we are able to run
    SMAP=${TMPPREF}_hash_cmd_map.txt
    rm -rf $SMAP
    MAPSIZE=$(cat service_map_${deployment}.txt | wc -l)
    for ((i=0;i<$MAPSIZE;i++)); do

      # Get the name/version regexp for the i-th service in the map
      read -r svc_name svc_vers svc_info <<< $(cat service_map_${deployment}.txt \
        | awk -v i=$i 'NR==i+1 {print $0}')

      # Find that name/version in the service listing
      hash=$(cat ${TMPPREF}_services.txt \
        | awk -v svc=$svc_name -v ver="^${svc_vers}" '$1==svc && $2~ver {print $3}')

      # Add all the hashes to a new file
      for h in $hash; do
        echo $h $svc_info >> $SMAP
      done

    done 

    # Get a comma-separated list of hashes
    hash_csv=$(cat $SMAP | awk '{print $1}' | sed -e "s/ /,/g")

    # Claim for the service
    itksnap-wt -dssp-services-claim $(echo $hash_csv | sed -e "s/ /,/g") picsl kubernetes-${deployment} 0 > ${TMPPREF}_claim.txt

    # Read the claim data
    read -r dummy ticket_id service_hash ticket_status <<< $(cat ${TMPPREF}_claim.txt | grep '^1>')

    # If there is a ticket claimed, send it to the k8s cluster for processing
    if [[ $ticket_id ]]; then

      # Report
      echo "$(date)   Claimed ticket $ticket_id for service $service_hash"

      # Get the parameters to use
      read -r dummy svc_cont svc_cmd svc_args <<< $(cat $SMAP | grep $service_hash)

      # Separate the arguments into separate strings
      svc_args_line=$(echo $(for arg in $svc_args; do echo "\"$arg\","; done) | sed -e "s/,$//")
      echo SVC_ARGS_LINE=$svc_args_line

      # Perform the substitution
      cat deployment_template.yml \
	      | sed -e "s|%container%|$svc_cont|g" \
	      | sed -e "s|%command%|$svc_cmd|g" \
	      | sed -e "s|%args%|$svc_args_line|g" \
	      | sed -e "s|%ticket_id%|$ticket_id|g" \
	      | sed -e "s|%deployment%|$deployment|g" \
	      > ${TMPPREF}_deployment_template.yml

      # Process the deployment
      kubectl apply -f ${TMPPREF}_deployment_template.yml

    else

      echo "$(date)   No eligible tickets in the queue"
      sleep 10

    fi

  done
}


dss_service_loop "$@"




