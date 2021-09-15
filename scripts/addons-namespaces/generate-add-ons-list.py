#!/usr/bin/env python3

import os
import string
import argparse
import oyaml as yaml

'''
This is a script for finding the manespace for each addon operator in managed-tenants repo and outputting them in a yaml file.  
'''

def main():

    parser = argparse.ArgumentParser(
        description="Finds all namespaces for managed-tenants addons and outputs them as a yaml document"
    )
    parser.add_argument(
        "--path",
        "-p",
        required=True,
        help="The path to managed-tenants/addons/ directory [required]",
    )
    parser.add_argument(
        "--output",
        "-o",
        help="The destination of the output yaml file. Default managed-cluster-config/resources/addons-namespaces/main.yaml ",
    )
    arguments = parser.parse_args()

    basepath = arguments.path

    addons = os.listdir(basepath)
   
    namescpace_dict = {}
    for operator in addons:
        filelist =[]
        path = basepath + operator +"/"
        for root, dirs, files in os.walk(path):
            for file in files:
                filelist.append(os.path.join(root,file))
            for file in filelist:
                namespace = ""
                if file.endswith('addon.yaml'):
                    file_to_search = open(file,"r")
                    for line in file_to_search.readlines():
                        if "targetNamespace" in line:
                            ns = line.split(":")[1].strip()
                            if namespace != ns:
                                namespace = ns
                                namescpace_dict[operator] = namespace 
    if arguments.output == None :
        output="managed-cluster-config/resources/addons-namespaces/main.yaml"
    else:
        output=arguments.output
    with open(output, 'w') as file:
        yaml.dump(namescpace_dict, file )
        
        
if __name__ == "__main__":
    main()
