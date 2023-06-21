import os
import secrets
import argparse
import logging
import grpc
import signal
import string
import random
from concurrent import futures

import service_pb2
import service_pb2_grpc

def generate_random_string(length):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

class StatelessService(service_pb2_grpc.StatelessVirtualServiceServicer):

    def Echo(self, request, context):
        logging.info("echo:%s", request.tag)
        return service_pb2.EchoRs(tag=request.tag)

    def Random(self, request, context):
        for _ in range(request.n):
            random_str = generate_random_string(32)
            logging.info("random:%s", random_str)
            yield service_pb2.RandomRs(random_value=random_str)

def serve():
    default_port = os.getenv('STATELESS_SERVICE_PORT', '8237')
    parser = argparse.ArgumentParser(description="A Stateless Service")
    parser.add_argument("--port", default=default_port, type=int, help='port number')
    args = parser.parse_args()

    # Configure logging
    logging.basicConfig(level=logging.INFO)

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    service_pb2_grpc.add_StatelessVirtualServiceServicer_to_server(StatelessService(), server)
    server.add_insecure_port('[::]:%s' % args.port)
    server.start()
    logging.info("port:%s", args.port)

    def stop_server(signal, frame):
        logging.info('stopping')
        server.stop(0)  # immediate shutdown
        logging.info('stopped')

    signal.signal(signal.SIGINT, stop_server)

    try:
        server.wait_for_termination()
    except Exception:
        logging.exception("termination error")

if __name__ == '__main__':
    serve()
