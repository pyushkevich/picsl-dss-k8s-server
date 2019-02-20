#!/bin/bash

# The services being handled by this script
SERVICE_NAMES=(ASHS-PMC)
SERVICE_VERSIONS=(".*")

# Continuous loop to check for tickets, claim them, and send to k8s cluster
function dss_service_loop()
{
  # Get the number of maximum concurrent pods allowed
  max_pods=${1?}

  # Infinite loop
  while true; do

    # Get the current pods
    kubectl get pods > /tmp/pods.txt

    if [[ $? -ne 0 ]]; then
      echo "$(date)   Pods listing failed"
      sleep 15
      continue
    fi

    # Count the number of pods currenly running
    n_pods=$(cat /tmp/pods.txt | awk '$3 == "Running" || $3 == "ContainerCreating" || $3 == "Pending" {print $1}' | wc -l | xargs)
    echo "$(date)   Currently $n_pods of $max_pods Pods are active"

    # If there is not space on the cluster, wait a little
    if [[ $n_pods -ge $max_pods ]]; then
      echo "$(date)   Maximum number of concurrent pods exceeded"
      sleep 15
      continue
    fi

    # Get a list of services we offer and select the subset handled on the cloud
    itksnap-wt -P -dssp-services-list > /tmp/services.txt
    
    hash_list=""
    for (( i=0; i<${#SERVICE_NAMES[*]}; i++)); do
      hash=$(cat /tmp/services.txt \
        | awk -v svc=${SERVICE_NAMES[i]} -v ver="${SERVICE_VERSIONS[i]}" '$1==svc && $2~ver {print $3}')
      hash_list=$(echo $hash_list $hash | xargs)
    done

    # Claim for the service
    itksnap-wt -dssp-services-claim $(echo $hash_list | sed -e "s/ /,/g") picsl kubernetes1 0 > /tmp/claim.txt

    # Read the claim data
    read -r dummy ticket_id service_hash ticket_status <<< $(cat /tmp/claim.txt | grep '^1>')

    # If there is a ticket claimed, send it to the k8s cluster for processing
    if [[ $ticket_id ]]; then

      # Report
      echo "$(date)   Claimed ticket $ticket_id for service $service_hash"

      # Process the deployment
      cat deployment_template.yml | sed -e "s/%ticket_id%/${ticket_id}/g" \
        > /tmp/deployment_template.yml 

      # Process the deployment
      kubectl apply -f /tmp/deployment_template.yml

    else

      echo "$(date)   No eligible tickets in the queue"
      sleep 10

    fi


  done
}




dss_service_loop 6   




