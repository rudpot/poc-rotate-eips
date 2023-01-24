# poc-rotate-eips

Demo how to rotate EIPs from EIP pool.

NOTE: rotating EIPs like this is probably not what you want and this is for exploration purposes only.


## Licence and Warranty

MIT No Attribution

Copyright 2022 Rudolf Potucek

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Launching the POC

We make the following assumptions:

* You have a default VPC with a public subnet in the VPC. If you don't have a default VPC, see [this knowledgebase article](https://aws.amazon.com/premiumsupport/knowledge-center/deleted-default-vpc/).

* You are testing in a region that has t4g.nano instances available.

* You have enough EIPs available - default allocation is 5 / account / region. If you do not have enough, try a different region or request an allocation increase as described in this [knowledgebase article](https://aws.amazon.com/premiumsupport/knowledge-center/ec2-instance-limit/).

* You have a bash shell with the AWS CLI and `jq` installed and credentials set for the account / region in which you want to do the testing. You can conveniently do this from [AWS CloudShell](https://console.aws.amazon.com/cloudshell/home). 



### Create the EIPs

We use a separate CloudFormation stack for EIPs to separate concerns. For this simple demo with 1 to 3 EIPs we use CloudFormation. If you would like to do this with more EIPs this would be easier using AWS CDK.

```bash
aws cloudformation deploy \
    --stack-name eip-poc-eips \
    --template-file template-allocate-eips.yaml \
    --parameter-overrides EipPoolSize=3
```

### Create consumer instances

We use a separate CloudFormation stack for EIPs to separate concerns. For this simple demo you can choose 1 or 2 instances. Extending this to 3 instances would be straightforward but would make it hard to see the rotations happening.

```bash
aws cloudformation deploy \
    --stack-name eip-poc-instances \
    --template-file template-create-instances.yaml \
    --parameter-overrides InstancePoolSize=1
```

### The script

This `rotate-ips.sh` script will do the following:

* find all available EIPs tagged with `Group` = `EipRotatePocEip` (https://github.com/rudpot/poc-rotate-eips/blob/main/rotate-ips.sh#L53)
* find all available EC2 instances tagged with `Group` = `EipRotatePocEip` (https://github.com/rudpot/poc-rotate-eips/blob/main/rotate-ips.sh#L70)
* loop over all instances (https://github.com/rudpot/poc-rotate-eips/blob/main/rotate-ips.sh#L77) and
  * disassociate the current EIP in favor of an auto-assigned IP (https://github.com/rudpot/poc-rotate-eips/blob/main/rotate-ips.sh#L88)
  * determine the appropriate index from the EIP list based on time of day, rotation frequency (https://github.com/rudpot/poc-rotate-eips/blob/main/rotate-ips.sh#L4), and instance offset (https://github.com/rudpot/poc-rotate-eips/blob/main/rotate-ips.sh#L98)
  * associate the selected EIP with the instance

To test the effect of the script, log into the [AWS EC2 Console](https://.console.aws.amazon.com/ec2/home?#Addresses:) and select "Elastic IPs". For better visibility select the gear icon on the top right and deselect all the options except "Allocation ID", "Associated Instance ID", and "Association ID". You should see something like this:

![No associations](start.img)

This shows that all three IPs are disassociated.

Perform the following actions:

1. In a bash shell run the `rotate-ips.sh` script and wait for it to finish
    ```bash
    bash rotate-ips.sh
    ```
2. refresh the EIP view in the EC2 console - you should now see one or two of the EIPs associated with your EC2 instance(s).
3. wait for 3 minutes
    ```bash
    sleep 180
    ```
4. run the `rotate-ips.sh` script again
5. refresh the EIP view in the EC2 console - you should now see one or two _different_ EIPs associated with your EC2 instance(s).

### Improving the script

* Doing this in bash isn't super legible but this was a customer request. Rewrite this in python for more powerful array and error handling.
* The script does not currently check whether the IPs would change and blindly follows the remove / allocate path even if the IP stays the same. Feel free to add a check for this and skip the operation if nothing changes. That way you can all it more frequently without impact.
* The script does not check if the EIP it wants to allocate is in use. Theoretically this doesn't matter because if it is, it should be rotated as part of the script as well. Feel free to make changes as you see fit.
* The script could be improved to skip the disassociation step and replace one EIP with another. Feel free to make changes as you see fit.

### Things that can't easily be improved

* You are rotating an external IP on your instance and that means that any in-flight transactions will break. You could experiment with having multiple IPs associated with an instance and rotating them with some drain time but it would likely not buy you much.

## Cleaning up

To avoid incurring charges from the instances and EIPs we created, make sure to delete the cloudformation stacks:

```bash
aws cloudformation delete-stack --stack-name eip-poc-instances
aws cloudformation wait stack-delete-complete --stack-name eip-poc-instances
aws cloudformation delete-stack --stack-name eip-poc-eips
```