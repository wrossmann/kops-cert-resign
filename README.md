# Re-Sign kOps Node Certificates

* When kOps spins up a cluster it generates an offline CA and stores it securely offline.
* When a kOps cluster node spins up it grabs the CA and signs its certificates for 465 days, plus a random number.
    * I assume that this is to prevent all your nodes from dying in unison.
* These certificates are _never_ updated by kOps, so if your cluster nodes get older than this they start getting "Unauthorized" errors via kubelet and kube-proxy.
* The prevailing wisdom is that you _should_ be performing cluster updates regularly, which will roll over all of your nodes and get you new nodes with new certs.

While I generally agree with this sentiment, adhering to it as dogma as the kOps/k8s folks do is extremely unproductive to those of us with real-world constraints that preclude us from easily rolling over our clusters like this.

So I have written these few scripts to allow me to sign new certificates for existing nodes in a kOps cluster.

## Assumptions

* You are running your cluster via AWS.
* Your AWS CLI client has the relevant credentials to access the kOps state bucket in S3.
    * Naturally, you can specify environment variables for the AWS CLI.
* You have SSH access to every cluster member.
    * Your current user will be used, or you can specify the `SSH_USER` environment variable.
* Your cluster nodes have openssl installed.

## Security

* Cluster node private keys never leave the node, only the CSR is sent back to the machine running the script.
* The CA private key _is_ necessarily fetched to the mechine running the script, but it is never written to disk.
    * Data is written from `aws s3api` into a named pipe, and stored in a bash variable.

## Execution

    ./kube_resign_certs.sh BUCKET_NAME CLUSTER_NAME HOST_NAME[ HOST_NAME...]

Eg:

    ./kube_resign_certs.sh myorg_kops_state k8s.orgname.internal node-0.k8s.orgname.internal node-1.k8s.orgname.internal

## Acknowledgements

I'd like to shout out to #kops-users on the k8s Slack server for motivating me to write this from scratch by their obstinate refusal to answer _any_ of my questions with anything other than variations of "just re-roll the cluster, dawg".

There are few things more motivating than unmitigated _spite_.

I _still_ have no idea how `nodeup` signs certificates when the node itself does not seem to have any access granted to the CA data either via the instance IAM profile, or the userdata in the instance template.

