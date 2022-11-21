set -o allexport; source ./.env; set +o allexport;
export $(grep -v '^#' .env | xargs -d '\n')

 forge create --rpc-url http://localhost:8545 --constructor-args 0xcF64698AFF7E5f27A11dff868AF228653ba53be0 0xBF57539473913685688d224ad4E262684B23dD4c --private-key $BOXCODE_PRIVATE_KEY contracts/TokenDistributor.sol:TokenDistributor 