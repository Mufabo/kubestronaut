# Profile `nocni`

A kind cluster with no CNI plugin at all. The nodes stay `NotReady`, and Pods
other than the static control-plane Pods stay `Pending` (or `ContainerCreating`)
until a lab installs a network. Used by Chapters 48 to 50, where the reader
installs one.
