from concurrent import futures
import argparse
import grpc
import hashlib
import random
import string
import os
import sys

# import the generated classes
sys.path.insert(0, os.getcwd())
import service_pb2
import service_pb2_grpc


# create a class to define the server functions
class StatelessVirtualServiceServicer(service_pb2_grpc.StatelessVirtualServiceServicer):

    def Hash(self, request, context):
        hashed_payload = hashlib.sha256(request.payload.encode()).hexdigest()
        return service_pb2.HashRs(hash_value=hashed_payload)

    def Random(self, request, context):
        random_str = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
        return service_pb2.RandomRs(random_value=random_str)


def serve():
    parser = argparse.ArgumentParser(description='Stateless Virtual Service.')
    parser.add_argument('--port', type=int, required=True, help='Port to run the service on')

    args = parser.parse_args()

    # create a gRPC server
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))

    # use the generated function `add_StatelessVirtualServiceServicer_to_server`
    # to add the defined class to the server
    service_pb2_grpc.add_StatelessVirtualServiceServicer_to_server(StatelessVirtualServiceServicer(), server)

    # listen on the given port
    server.add_insecure_port('[::]:' + str(args.port))
    server.start()
    server.wait_for_termination()


if __name__ == "__main__":
    serve()
