awk '/^\[(.*)\]/ {cat=substr($0,2,length($0)-2)} /^[a-zA-Z0-9]/ {sub(/=.*/,""); print cat "."$0}' locale/*/* | sort | uniq