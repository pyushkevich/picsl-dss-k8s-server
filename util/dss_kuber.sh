#!/bin/bash

# Collection of kubernettes scripts to create clusters and such for DSS on the cloud

# This function creates a blank Kubernettes cluster 
function make_cluster()
{
  cluster_name=${1?}

  # Create a cluster without any nodes
  gcloud container clusters create --num-nodes=1 $cluster_name

  # Create a name for the pool
  pool_name="${cluster_name}-worker-pool"

  # Create a node pool for ASHS
  gcloud container node-pools create \
    --cluster=$cluster_name \
    --disk-size 200GB -m n1-standard-16 \
    --enable-autoscaling --min-nodes 0 --max-nodes 6 --preemptible \
    --num-nodes=1 \
    $pool_name
}

# This function creates a permanent volume and volume claim around the GCE 
# disk containing ASHS atlases
function make_pvc()
{
  cluster_name=${1?}

  # Create the PV object
  cat > /tmp/create_pd.yaml <<-CREATE_PD
		apiVersion: v1
		kind: PersistentVolume
		metadata:
		  name: pv-ashs-atlases
		spec:
		  storageClassName: ""
		  capacity:
		    storage: 200G
		  accessModes:
		    - ReadOnlyMany
		  gcePersistentDisk:
		    pdName: ashs-atlases
		    fsType: ext4
		---
		apiVersion: v1
		kind: PersistentVolumeClaim
		metadata:
		  name: pvc-ashs-atlases
		spec:
		  storageClassName: ""
		  volumeName: pv-ashs-atlases
		  accessModes:
		    - ReadOnlyMany
		  resources:
		    requests:
		      storage: 200G
CREATE_PD

  # Execute
  kubectl apply -f /tmp/create_pd.yaml
}

# This function creates login credentials for the alfabis server by 
# copying them from the local machine. This is not the most secure
# way of doing things, but passing a token around is error-prone because
# of the single-use nature of tokens
function make_secret()
{
  # Delete the secret if it already exists
  kubectl delete --ignore-not-found secrets alfabis-cookie

  # Create a new secret
  local PARAM=""
  for fn in $(ls $HOME/.alfabis); do
    PARAM="$PARAM --from-file=${fn}=$HOME/.alfabis/${fn}"
  done

  kubectl create secret generic alfabis-cookie $PARAM
  kubectl get secrets
}


# Main entrypoint
if [[ $# -gt 0 ]]; then
  cmd=$1
  shift
  $cmd "$@"
else
  echo "No function specified"
fi


