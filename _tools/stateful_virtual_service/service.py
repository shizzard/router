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

# Global dictionary to store agent data
agents = {}

class StatefulService(service_pb2_grpc.StatefulVirtualServiceServicer):
    ROUTER_HEADER_AGENT_ID = 'x-router-agent-id'
    ROUTER_HEADER_AGENT_INSTANCE = 'x-router-agent-instance'

    def Get(self, request, context):
        logging.info("get")
        if not self._validate_headers(context.invocation_metadata()):
            logging.info('missing-headers')
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, 'Invalid Request: Missing headers')

        agent_id = None
        agent_instance = None

        for metadatum in context.invocation_metadata():
            if metadatum.key.lower() == StatefulService.ROUTER_HEADER_AGENT_ID:
                agent_id = metadatum.value
            elif metadatum.key.lower() == StatefulService.ROUTER_HEADER_AGENT_INSTANCE:
                agent_instance = metadatum.value

        agent_key = (agent_id, agent_instance)
        logging.info("agent:%s:%s" % (agent_id, agent_instance))

        if agent_key not in agents:
            agents[agent_key] = {}

        data = agents[agent_key]
        key = request.key
        logging.info("key:%s" % key)

        value = data.get(key, 0)
        logging.info("value:%s" % value)

        return service_pb2.GetRs(key=key, value=value)

    def Set(self, request, context):
        logging.info("set")
        if not self._validate_headers(context.invocation_metadata()):
            logging.info('missing-headers')
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, 'Invalid Request: Missing headers')

        agent_id = None
        agent_instance = None

        for metadatum in context.invocation_metadata():
            if metadatum.key.lower() == StatefulService.ROUTER_HEADER_AGENT_ID:
                agent_id = metadatum.value
            elif metadatum.key.lower() == StatefulService.ROUTER_HEADER_AGENT_INSTANCE:
                agent_instance = metadatum.value

        agent_key = (agent_id, agent_instance)
        logging.info("agent:%s:%s" % (agent_id, agent_instance))

        if agent_key not in agents:
            agents[agent_key] = {}

        data = agents[agent_key]
        key = request.key
        logging.info("key:%s" % key)
        value = request.value
        logging.info("value:%s" % value)

        data[key] = value

        return service_pb2.SetRs()

    def _validate_headers(self, metadata):
        required_headers = {
            StatefulService.ROUTER_HEADER_AGENT_ID.lower(),
            StatefulService.ROUTER_HEADER_AGENT_INSTANCE.lower()
        }

        received_headers = set()
        for metadatum in metadata:
            received_headers.add(metadatum.key.lower())

        return required_headers.issubset(received_headers)

def serve():
    default_port = os.getenv('STATEFUL_SERVICE_PORT', '8337')
    parser = argparse.ArgumentParser(description='A Stateful Service')
    parser.add_argument("--port", default=default_port, type=int, help='port number')
    args = parser.parse_args()

    # Configure logging
    logging.basicConfig(level=logging.INFO)

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    service_pb2_grpc.add_StatefulVirtualServiceServicer_to_server(StatefulService(), server)
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
        logging.exception("termination-error")

if __name__ == '__main__':
    serve()
