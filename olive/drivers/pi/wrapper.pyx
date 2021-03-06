#cython: language_level=3

from cpython cimport bool as pybool
cimport cython
from cython cimport view
from libcpp.vector cimport vector

from enum import auto, Enum, IntEnum

from gcs2 cimport *

##

class ReferenceMode(IntEnum):
    Absolute = 1
    Relative = 0

class ReferenceStrategy(Enum):
    ReferenceSwitch = auto()
    NegativeLimit   = auto()
    PositiveLimit   = auto()

class ServoState(IntEnum):
    OpenLoop    = 0
    ClosedLoop  = 1

##

cdef translate_error(int err_id, int nbytes=1024):
    cdef char[::1] buffer = view.array(
        shape=(nbytes, ), itemsize=sizeof(char), format='c'
    )
    cdef char *c_buffer = &buffer[0]

    ret = PI_TranslateError(err_id, c_buffer, nbytes)
    assert ret > 0, f"message buffer ({nbytes} bytes) is too small"

    return c_buffer.decode('ascii', errors='replace')

@cython.final
cdef class Communication:
    ##
    ## error
    ##
    @staticmethod
    cdef check_error(int ret):
        if ret < 0:
            print(f'err_id: {ret}')
            raise RuntimeError(translate_error(ret))

    ##
    ## communication
    ##
    ### USB ###
    cpdef enumerate_usb(self, str keyword="", int nbytes=1024):
        cdef char[::1] buffer = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_buffer = &buffer[0]

        b_keyword = keyword.encode('ascii')
        cdef char *c_keyword = b_keyword

        ret = PI_EnumerateUSB(c_buffer, nbytes, c_keyword)
        Communication.check_error(ret)

        return c_buffer.decode('ascii', errors='replace')

    cpdef connect_usb(self, str desc, int baudrate=-1):
        b_desc = desc.encode('ascii')
        cdef char *c_desc = b_desc

        if baudrate < 0:
            ret = PI_ConnectUSB(c_desc)
        else:
            ret = PI_ConnectUSBWithBaudRate(c_desc, baudrate)
        Communication.check_error(ret)

        return ret

    ### async connection ###
    cpdef try_connect_usb(self, str desc):
        b_desc = desc.encode('ascii')
        cdef char *c_desc = b_desc

        ret = PI_TryConnectUSB(c_desc)
        Communication.check_error(ret)

        return ret

    cpdef is_connecting(self, int thread_id):
        cdef int status
        ret = PI_IsConnecting(thread_id, &status)
        Communication.check_error(ret)
        return status > 0

    cpdef get_controller_id(self, int thread_id):
        ret = PI_GetControllerID(thread_id)
        Communication.check_error(ret)
        return ret

    cpdef is_connected(self, int ctrl_id):
        ret = PI_IsConnected(ctrl_id)
        return ret > 0

    ### daisy chain ###
    cpdef set_daisy_chain_scan_max_device_id(self, int max_id):
        ret = PI_SetDaisyChainScanMaxDeviceID(max_id)
        Communication.check_error(ret)

    cpdef open_usb_daisy_chain(self, str desc, int nbytes=1024):
        """
        Open a USB interface to a daisy chain.

        Note that calling this function does not open a daisy chain device, to get access to one, one must call `connect_daisy_chain_device` later on.

        Args:
            desc (str): description of the controller
            nbytes (int, optional): size of the buffer to receive IDN
        """
        cdef char[::1] buffer = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_buffer = &buffer[0]

        b_desc = desc.encode('ascii')
        cdef char *c_desc = b_desc

        cdef int n_dev
        ret = PI_OpenUSBDaisyChain(c_desc, &n_dev, c_buffer, nbytes)
        Communication.check_error(ret)

        return ret, n_dev, c_buffer.decode('ascii', errors='replace')

    cpdef connect_daisy_chain_device(self, int daisy_id, int index):
        """
        Open a daisy chain device.

        Before connecting a daisy cahin device, the daisy chain port has to be opened using `open_usb_daisy_chain`.

        Args:
            daisy_id (int): ID of the daisy chain port
            index (int): index of the daisy chain device to use, [1, N]
        """
        ret = PI_ConnectDaisyChainDevice(daisy_id, index)
        Communication.check_error(ret)
        return ret

    cpdef close_daisy_chain(self, daisy_id):
        PI_CloseDaisyChain(daisy_id)

    ### termination ###
    cpdef close_connection(self, int ctrl_id):
        PI_CloseConnection(ctrl_id)


cdef class ControllerCommand:
    """
    Wrapper class for GCS2 commands. These commands are controller dependents.
    """
    cdef readonly int ctrl_id

    def __cinit__(self, int ctrl_id, *args):
        self.ctrl_id = ctrl_id

    cdef check_error(self, int ret):
        if ret > 0:
            # true, successful
            return
        err_id = PI_GetError(self.ctrl_id)
        raise RuntimeError(translate_error(err_id))

    ##

    cpdef set_error_check(self, pybool err_check):
        PI_SetErrorCheck(self.ctrl_id, err_check)

    ## query status ##
    cpdef is_moving(self, str axes=""):
        """#5"""
        b_axes = axes.encode('ascii')
        cdef char *c_axes = b_axes

        cdef int status
        ret = PI_IsMoving(self.ctrl_id, c_axes, &status)
        self.check_error(ret)
        return status > 0

    cpdef is_controller_ready(self):
        """#7"""
        cdef int status
        ret = PI_IsControllerReady(self.ctrl_id, &status)
        self.check_error(ret)
        return status > 0

    cpdef is_running_macro(self):
        """#8"""
        cdef int status
        ret = PI_IsRunningMacro(self.ctrl_id, &status)
        self.check_error(ret)
        return status > 0

    ## axis control ##
    cpdef get_axes_enable_status(self, str axes):
        """qEAX"""
        pass

    cpdef set_axes_enable_status(self, str axes, pybool state):
        """EAX"""
        pass

    cpdef get_axes_id(self, pybool include_deactivated=True, int nbytes=512):
        """qSAI/qSAI_ALL"""
        cdef char[::1] buffer = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_buffer = &buffer[0]

        if include_deactivated:
            ret = PI_qSAI_ALL(self.ctrl_id, c_buffer, nbytes)
        else:
            ret = PI_qSAI(self.ctrl_id, c_buffer, nbytes)
        self.check_error(ret)

        return c_buffer.decode('ascii', errors='replace')

    ## motions ##
    cpdef stop_all(self):
        """#24"""
        ret = PI_StopAll(self.ctrl_id)
        self.check_error(ret)

    ## utils ##
    cpdef get_available_commands(self, int nbytes=512):
        """qHLP"""
        cdef char[::1] buffer = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_buffer = &buffer[0]

        ret = PI_qHLP(self.ctrl_id, c_buffer, nbytes)
        self.check_error(ret)

        return c_buffer.decode('ascii', errors='replace')

    cpdef get_identification_string(self, int nbytes=256):
        """qIDN"""
        cdef char[::1] buffer = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_buffer = &buffer[0]

        ret = PI_qIDN(self.ctrl_id, c_buffer, nbytes)
        self.check_error(ret)

        return c_buffer.decode('ascii', errors='replace')

    cpdef get_available_parameters(self, int nbytes=512):
        """qHPA"""
        cdef char[::1] buffer = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_buffer = &buffer[0]

        ret = PI_qHPA(self.ctrl_id, c_buffer, nbytes)
        self.check_error(ret)

        return c_buffer.decode('ascii', errors='replace')

    cpdef get_valid_character_set(self, int nbytes=512):
        """qTVI"""
        cdef char[::1] buffer = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_buffer = &buffer[0]

        ret = PI_qTVI(self.ctrl_id, c_buffer, nbytes)
        self.check_error(ret)

        return c_buffer.decode('ascii', errors='replace')

    cpdef get_version(self, int nbytes=512):
        """qVER"""
        cdef char[::1] buffer = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_buffer = &buffer[0]

        ret = PI_qVER(self.ctrl_id, c_buffer, nbytes)
        self.check_error(ret)

        return c_buffer.decode('ascii', errors='replace')


@cython.final
cdef class AxisCommand(ControllerCommand):
    """
    Wrapper class for GCS2 commands. These commands are axis dependents.
    """
    cdef readonly bytes axis_id

    def __cinit__(self, int ctrl_id, str axis_id):
        self.ctrl_id, self.axis_id = ctrl_id, axis_id.encode('ascii')

    ##

    cpdef get_reference_mode(self):
        """qRON"""
        cdef char *c_axis_id = self.axis_id

        cdef int mode
        ret = PI_qRON(self.ctrl_id, c_axis_id, &mode)
        self.check_error(ret)

        return ReferenceMode(mode)

    cpdef set_reference_mode(self, int mode: ReferenceMode):
        """RON"""
        cdef char *c_axis_id = self.axis_id

        ret = PI_RON(self.ctrl_id, c_axis_id, &mode)
        self.check_error(ret)

    cpdef is_referenced(self):
        cdef char *c_axis_id = self.axis_id

        cdef int state
        ret = PI_qFRF(self.ctrl_id, c_axis_id, &state)
        self.check_error(ret)

        return state > 0

    cpdef start_reference_movement(
        self, strategy: ReferenceStrategy = ReferenceStrategy.ReferenceSwitch
    ):
        cdef char *c_axis_id = self.axis_id

        if strategy == ReferenceStrategy.ReferenceSwitch:
            ret = PI_FRF(self.ctrl_id, c_axis_id)
        elif strategy == ReferenceStrategy.NegativeLimit:
            ret = PI_FNL(self.ctrl_id, c_axis_id)
        elif strategy == ReferenceStrategy.PositiveLimit:
            ret = PI_FPL(self.ctrl_id, c_axis_id)
        else:
            ret = 0
        self.check_error(ret)

    ##

    cpdef go_to_home(self):
        """GOH"""
        cdef char *c_axis_id = self.axis_id

        cdef int status
        ret = PI_GOH(self.ctrl_id, c_axis_id)
        self.check_error(ret)

    cpdef halt(self, str axis =""):
        """
        HLT

        Halt the motion of given axes smoothly.
        """
        cdef char *c_axis_id = self.axis_id

        cdef int status
        ret = PI_HLT(self.ctrl_id, c_axis_id)
        self.check_error(ret)

    ##

    cpdef get_current_position(self):
        """qPOS"""
        cdef char *c_axis_id = self.axis_id

        cdef double value
        ret = PI_qPOS(self.ctrl_id, c_axis_id, &value)
        self.check_error(ret)

        return value

    cpdef set_current_position(self, double value):
        """POS"""
        cdef char *c_axis_id = self.axis_id

        ret = PI_POS(self.ctrl_id, c_axis_id, &value)
        self.check_error(ret)

    cpdef set_target_position(self, double value):
        """MOV"""
        cdef char *c_axis_id = self.axis_id

        ret = PI_MOV(self.ctrl_id, c_axis_id, &value)
        self.check_error(ret)

    cpdef set_relative_target_position(self, double value):
        """MVR"""
        cdef char *c_axis_id = self.axis_id

        ret = PI_MVR(self.ctrl_id, c_axis_id, &value)
        self.check_error(ret)

    ##

    cpdef get_velocity(self):
        """qVEL"""
        cdef char *c_axis_id = self.axis_id

        cdef double value
        ret = PI_qVEL(self.ctrl_id, c_axis_id, &value)
        self.check_error(ret)

        return value

    cpdef set_velocity(self, double vel):
        """VEL"""
        cdef char *c_axis_id = self.axis_id

        ret = PI_VEL(self.ctrl_id, c_axis_id, &vel)
        self.check_error(ret)

    ##

    cpdef get_acceleration(self):
        """qACC"""
        cdef char *c_axis_id = self.axis_id

        cdef double value
        ret = PI_qACC(self.ctrl_id, c_axis_id, &value)
        self.check_error(ret)

        return value

    cpdef set_acceleration(self, double acc):
        """ACC"""
        cdef char *c_axis_id = self.axis_id

        ret = PI_ACC(self.ctrl_id, c_axis_id, &acc)
        self.check_error(ret)

    ##

    cpdef get_travel_range_min(self):
        """qTMN"""
        cdef char *c_axis_id = self.axis_id

        cdef double value
        ret = PI_qTMN(self.ctrl_id, c_axis_id, &value)
        self.check_error(ret)

        return value

    cpdef get_travel_range_max(self):
        """qTMX"""
        cdef char *c_axis_id = self.axis_id

        cdef double value
        ret = PI_qTMX(self.ctrl_id, c_axis_id, &value)
        self.check_error(ret)

        return value

    ##

    cpdef get_stage_type(self, int nbytes=512):
        """qCST"""
        cdef char[::1] buffer = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_buffer = &buffer[0]

        cdef char *c_axis_id = self.axis_id
        ret = PI_qCST(self.ctrl_id, c_axis_id, c_buffer, nbytes)
        self.check_error(ret)

        return c_buffer.decode('ascii', errors='replace')

    cpdef get_parameter(
        self, unsigned int parameter, pybool volatile=False, int nelem=1, int nbytes=64
    ):
        """qSEP/qSPA"""
        cdef char *c_axis_id = self.axis_id

        cdef double[::1] values = view.array(
            shape=(nelem, ), itemsize=sizeof(double), format='g'
        )
        cdef double *c_values = &values[0]

        cdef char[::1] string = view.array(
            shape=(nbytes, ), itemsize=sizeof(char), format='c'
        )
        cdef char *c_string = &string[0]

        if volatile:
            ret = PI_qSPA(
                self.ctrl_id,
                c_axis_id,
                &parameter,
                c_values,
                c_string,
                nbytes
            )
        else:
            ret = PI_qSEP(
                self.ctrl_id,
                c_axis_id,
                &parameter,
                c_values,
                c_string,
                nbytes
            )
        self.check_error(ret)

        return values, c_string.decode('ascii', errors='replace')

    cpdef set_parameter(
        self,
        unsigned int parameter,
        values,
        str string,
        pybool volatile=False,
        int nbytes=64
    ):
        """SEP/SPA"""
        cdef char *c_axis_id = self.axis_id

        cdef vector[double] v_values = values

        b_string = string.encode('ascii')
        cdef char *c_string = b_string

        if volatile:
            ret = PI_SPA(
                self.ctrl_id,
                c_axis_id,
                &parameter,
                v_values.data(),
                c_string
            )
        else:
            ret = PI_SEP(
                self.ctrl_id,
                "100".encode('ascii'),
                c_axis_id,
                &parameter,
                v_values.data(),
                c_string
            )
        self.check_error(ret)

    cpdef set_servo_state(self, int state: ServoState):
        """SVO"""
        cdef char *c_axis_id = self.axis_id

        ret = PI_SVO(self.ctrl_id, c_axis_id, &state)
        self.check_error(ret)
