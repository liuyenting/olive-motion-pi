import logging
from pprint import pprint

import coloredlogs

from olive.drivers.pi import GCS2

coloredlogs.install(
    level="DEBUG", fmt="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S"
)

logger = logging.getLogger(__name__)

# init driver
driver = GCS2()
driver.initialize()

try:
    devices = driver.enumerate_devices()
    pprint(devices)

    controller = devices[0]
    controller.open()
    try:
        print(">>> HELP")
        pprint(controller.get_property("help"))
        print("<<< HELP")
        print()

        print(">>> PARAMETERS")
        pprint(controller.get_property("parameters"))
        print("<<< PARAMETERS")
        print()
    finally:
        controller.close()
finally:
    driver.shutdown()
