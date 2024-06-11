## System Setup

This suite integrates a full local or forked deployment of the EigenLayer system. 

The EigenLayer system is added as a dependency in the eigenlayer-fuzzing submodule. 

To deploy the EigenLayer system in RenzoSetupV2 it inherits from EigenLayerSetupV2 and calls the `deployEigenLayerLocal` or `deployEigenLayerForked`. 

NOTE: `deployEigenLayerForked` doesn't currently work and requires further changes to the eigenlayer-fuzzing submodule. 