## System Setup

This suite integrates a full local or forked deployment of the EigenLayer system. 

The EigenLayer system is added as a dependency in the eigenlayer-fuzzing submodule. 

To deploy the EigenLayer system in RenzoSetupV2 it inherits from EigenLayerSetupV2 and calls the `deployEigenLayerLocal` or `deployEigenLayerForked`. 

NOTE: `deployEigenLayerForked` doesn't currently work and requires further changes to the eigenlayer-fuzzing submodule. 

### Versioning

The decision was made to split the fuzzing suite into a V2 after implementing the token + strategy and OperatorDelegator deployment via `restakeManager_deployTokenStratOperatorDelegator` as this changed the core of the Renzo system deployment and to allow testing of the multi deployer system without breaking the original implementation. 

The original V1 implementation deploys the Renzo system with two collateral tokens and two OperatorDelegators, with the strategies already having been deployed in the EigenLayerSetup. 