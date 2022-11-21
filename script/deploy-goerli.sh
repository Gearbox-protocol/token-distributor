set -o allexport; source ./.env; set +o allexport;
export $(grep -v '^#' .env | xargs -d '\n')

 forge create --rpc-url $ETH_GOERLI_PROVIDER --constructor-args 0x95f4cea53121b8A2Cb783C6BFB0915cEc44827D3 0x317980f50333ff3E28A0B947B05308BaC51262FE --private-key $GOERLI_PRIVATE_KEY --verify contracts/TokenDistributor.sol:TokenDistributor