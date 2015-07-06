#cython: boundscheck=False
#cython: wraparound=False
#cython: cdivision=False
"""
State Space Models

Author: Chad Fulton  
License: Simplified-BSD
"""

# ## Constants

# ### Filters
# TODO note that only the conventional filter is implemented
cdef int FILTER_CONVENTIONAL = 0x01     # Durbin and Koopman (2012), Chapter 4
cdef int FILTER_EXACT_INITIAL = 0x02    # ibid., Chapter 5.6
cdef int FILTER_AUGMENTED = 0x04        # ibid., Chapter 5.7
cdef int FILTER_SQUARE_ROOT = 0x08      # ibid., Chapter 6.3
cdef int FILTER_UNIVARIATE = 0x10       # ibid., Chapter 6.4
cdef int FILTER_COLLAPSED = 0x20        # ibid., Chapter 6.5
cdef int FILTER_EXTENDED = 0x40         # ibid., Chapter 10.2
cdef int FILTER_UNSCENTED = 0x80        # ibid., Chapter 10.3

# ### Inversion methods
# Methods by which the terms using the inverse of the forecast error
# covariance matrix are solved.
cdef int INVERT_UNIVARIATE = 0x01
cdef int SOLVE_LU = 0x02
cdef int INVERT_LU = 0x04
cdef int SOLVE_CHOLESKY = 0x08
cdef int INVERT_CHOLESKY = 0x10

# ### Numerical Stability methods
# Methods to improve numerical stability
cdef int STABILITY_FORCE_SYMMETRY = 0x01

# ### Memory conservation options
cdef int MEMORY_STORE_ALL = 0
cdef int MEMORY_NO_FORECAST = 0x01
cdef int MEMORY_NO_PREDICTED = 0x02
cdef int MEMORY_NO_FILTERED = 0x04
cdef int MEMORY_NO_LIKELIHOOD = 0x08
cdef int MEMORY_CONSERVE = (
    MEMORY_NO_FORECAST | MEMORY_NO_PREDICTED | MEMORY_NO_FILTERED |
    MEMORY_NO_LIKELIHOOD
)

# Typical imports
import numpy as np
import warnings
cimport numpy as np
cimport cython

np.import_array()

# ## Math Functions
# Real and complex log and abs functions
from libc.math cimport log as dlog, abs as dabs
from numpy cimport npy_cdouble

cdef extern from "numpy/npy_math.h":
    np.float64_t NPY_PI
    np.float64_t npy_cabs(np.npy_cdouble z)
    np.npy_cdouble npy_clog(np.npy_cdouble z)

cdef inline np.float64_t zabs(np.complex128_t z):
    return npy_cabs((<np.npy_cdouble *> &z)[0])

cdef inline np.complex128_t zlog(np.complex128_t z):
    cdef np.npy_cdouble x
    x = npy_clog((<np.npy_cdouble*> &z)[0])
    return (<np.complex128_t *> &x)[0]

cdef extern from "capsule.h":
    void *Capsule_AsVoidPtr(object ptr)

# ## BLAS / LAPACK functions

# `blas_lapack.pxd` contains typedef statements for BLAS and LAPACK functions
from statsmodels.src.blas_lapack cimport *

try:
    # Scipy >= 0.12.0 exposes Fortran BLAS functions directly
    from scipy.linalg.blas import cgerc
except:
    # Scipy < 0.12.0 exposes Fortran BLAS functions in the `fblas` submodule
    from scipy.linalg.blas import fblas as blas
else:
    from scipy.linalg import blas

try:
    # Scipy >= 0.12.0 exposes Fortran LAPACK functions directly
    from scipy.linalg.lapack import cgbsv
except:
    # Scipy < 0.12.0 exposes Fortran LAPACK functions in the `flapack` submodule
    from scipy.linalg.lapack import flapack as lapack
else:
    from scipy.linalg import lapack
cdef zgemm_t *zgemm = <zgemm_t*>Capsule_AsVoidPtr(blas.zgemm._cpointer)
cdef zgemv_t *zgemv = <zgemv_t*>Capsule_AsVoidPtr(blas.zgemv._cpointer)
cdef zcopy_t *zcopy = <zcopy_t*>Capsule_AsVoidPtr(blas.zcopy._cpointer)
cdef zaxpy_t *zaxpy = <zaxpy_t*>Capsule_AsVoidPtr(blas.zaxpy._cpointer)
cdef zscal_t *zscal = <zscal_t*>Capsule_AsVoidPtr(blas.zscal._cpointer)
cdef zgetrf_t *zgetrf = <zgetrf_t*>Capsule_AsVoidPtr(lapack.zgetrf._cpointer)
cdef zgetri_t *zgetri = <zgetri_t*>Capsule_AsVoidPtr(lapack.zgetri._cpointer)
cdef zgetrs_t *zgetrs = <zgetrs_t*>Capsule_AsVoidPtr(lapack.zgetrs._cpointer)
cdef zpotrf_t *zpotrf = <zpotrf_t*>Capsule_AsVoidPtr(lapack.zpotrf._cpointer)
cdef zpotri_t *zpotri = <zpotri_t*>Capsule_AsVoidPtr(lapack.zpotri._cpointer)
cdef zpotrs_t *zpotrs = <zpotrs_t*>Capsule_AsVoidPtr(lapack.zpotrs._cpointer)
cdef cgemm_t *cgemm = <cgemm_t*>Capsule_AsVoidPtr(blas.cgemm._cpointer)
cdef cgemv_t *cgemv = <cgemv_t*>Capsule_AsVoidPtr(blas.cgemv._cpointer)
cdef ccopy_t *ccopy = <ccopy_t*>Capsule_AsVoidPtr(blas.ccopy._cpointer)
cdef caxpy_t *caxpy = <caxpy_t*>Capsule_AsVoidPtr(blas.caxpy._cpointer)
cdef cscal_t *cscal = <cscal_t*>Capsule_AsVoidPtr(blas.cscal._cpointer)
cdef cgetrf_t *cgetrf = <cgetrf_t*>Capsule_AsVoidPtr(lapack.cgetrf._cpointer)
cdef cgetri_t *cgetri = <cgetri_t*>Capsule_AsVoidPtr(lapack.cgetri._cpointer)
cdef cgetrs_t *cgetrs = <cgetrs_t*>Capsule_AsVoidPtr(lapack.cgetrs._cpointer)
cdef cpotrf_t *cpotrf = <cpotrf_t*>Capsule_AsVoidPtr(lapack.cpotrf._cpointer)
cdef cpotri_t *cpotri = <cpotri_t*>Capsule_AsVoidPtr(lapack.cpotri._cpointer)
cdef cpotrs_t *cpotrs = <cpotrs_t*>Capsule_AsVoidPtr(lapack.cpotrs._cpointer)
cdef dgemm_t *dgemm = <dgemm_t*>Capsule_AsVoidPtr(blas.dgemm._cpointer)
cdef dgemv_t *dgemv = <dgemv_t*>Capsule_AsVoidPtr(blas.dgemv._cpointer)
cdef dcopy_t *dcopy = <dcopy_t*>Capsule_AsVoidPtr(blas.dcopy._cpointer)
cdef daxpy_t *daxpy = <daxpy_t*>Capsule_AsVoidPtr(blas.daxpy._cpointer)
cdef dscal_t *dscal = <dscal_t*>Capsule_AsVoidPtr(blas.dscal._cpointer)
cdef dgetrf_t *dgetrf = <dgetrf_t*>Capsule_AsVoidPtr(lapack.dgetrf._cpointer)
cdef dgetri_t *dgetri = <dgetri_t*>Capsule_AsVoidPtr(lapack.dgetri._cpointer)
cdef dgetrs_t *dgetrs = <dgetrs_t*>Capsule_AsVoidPtr(lapack.dgetrs._cpointer)
cdef dpotrf_t *dpotrf = <dpotrf_t*>Capsule_AsVoidPtr(lapack.dpotrf._cpointer)
cdef dpotri_t *dpotri = <dpotri_t*>Capsule_AsVoidPtr(lapack.dpotri._cpointer)
cdef dpotrs_t *dpotrs = <dpotrs_t*>Capsule_AsVoidPtr(lapack.dpotrs._cpointer)
cdef sgemm_t *sgemm = <sgemm_t*>Capsule_AsVoidPtr(blas.sgemm._cpointer)
cdef sgemv_t *sgemv = <sgemv_t*>Capsule_AsVoidPtr(blas.sgemv._cpointer)
cdef scopy_t *scopy = <scopy_t*>Capsule_AsVoidPtr(blas.scopy._cpointer)
cdef saxpy_t *saxpy = <saxpy_t*>Capsule_AsVoidPtr(blas.saxpy._cpointer)
cdef sscal_t *sscal = <sscal_t*>Capsule_AsVoidPtr(blas.sscal._cpointer)
cdef sgetrf_t *sgetrf = <sgetrf_t*>Capsule_AsVoidPtr(lapack.sgetrf._cpointer)
cdef sgetri_t *sgetri = <sgetri_t*>Capsule_AsVoidPtr(lapack.sgetri._cpointer)
cdef sgetrs_t *sgetrs = <sgetrs_t*>Capsule_AsVoidPtr(lapack.sgetrs._cpointer)
cdef spotrf_t *spotrf = <spotrf_t*>Capsule_AsVoidPtr(lapack.spotrf._cpointer)
cdef spotri_t *spotri = <spotri_t*>Capsule_AsVoidPtr(lapack.spotri._cpointer)
cdef spotrs_t *spotrs = <spotrs_t*>Capsule_AsVoidPtr(lapack.spotrs._cpointer)

cdef sdot_t *sdot = <sdot_t*>Capsule_AsVoidPtr(blas.sdot._cpointer)
cdef ddot_t *ddot = <ddot_t*>Capsule_AsVoidPtr(blas.ddot._cpointer)
cdef cdotu_t *cdot = <cdotu_t*>Capsule_AsVoidPtr(blas.cdotu._cpointer)
cdef zdotu_t *zdot = <zdotu_t*>Capsule_AsVoidPtr(blas.zdotu._cpointer)

cdef int FORTRAN = 1

# Array shape validation
cdef validate_matrix_shape(str name, Py_ssize_t *shape, int nrows, int ncols, nobs=None):
    if not shape[0] == nrows:
        raise ValueError('Invalid shape for %s matrix: requires %d rows,'
                         ' got %d' % (name, nrows, shape[0]))
    if not shape[1] == ncols:
        raise ValueError('Invalid shape for %s matrix: requires %d columns,'
                         'got %d' % (name, shape[1], shape[1]))
    if nobs is not None and shape[2] not in [1, nobs]:
        raise ValueError('Invalid time-varying dimension for %s matrix:'
                         ' requires 1 or %d, got %d' % (name, nobs, shape[2]))

cdef validate_vector_shape(str name, Py_ssize_t *shape, int nrows, nobs = None):
    if not shape[0] == nrows:
        raise ValueError('Invalid shape for %s vector: requires %d rows,'
                         ' got %d' % (name, nrows, shape[0]))
    if nobs is not None and not shape[1] in [1, nobs]:
        raise ValueError('Invalid time-varying dimension for %s vector:'
                         ' requires 1 or %d got %d' % (name, nobs, shape[1]))

## State Space Representation
cdef class zStatespace(object):
    """
    zStatespace(obs, design, obs_intercept, obs_cov, transition, state_intercept, selection, state_cov)

    *See Durbin and Koopman (2012), Chapter 4 for all notation*
    """

    # ### State space representation
    # 
    # $$
    # \begin{align}
    # y_t & = Z_t \alpha_t + d_t + \varepsilon_t \hspace{3em} & \varepsilon_t & \sim N(0, H_t) \\\\
    # \alpha_{t+1} & = T_t \alpha_t + c_t + R_t \eta_t & \eta_t & \sim N(0, Q_t) \\\\
    # & & \alpha_1 & \sim N(a_1, P_1)
    # \end{align}
    # $$
    # 
    # $y_t$ is $p \times 1$  
    # $\varepsilon_t$ is $p \times 1$  
    # $\alpha_t$ is $m \times 1$  
    # $\eta_t$ is $r \times 1$  
    # $t = 1, \dots, T$

    # `nobs` $\equiv T$ is the length of the time-series  
    # `k_endog` $\equiv p$ is dimension of observation space  
    # `k_states` $\equiv m$ is the dimension of the state space  
    # `k_posdef` $\equiv r$ is the dimension of the state shocks  
    # *Old notation: T, n, k, g*
    cdef readonly int nobs, k_endog, k_states, k_posdef
    
    # `obs` $\equiv y_t$ is the **observation vector** $(p \times T)$  
    # `design` $\equiv Z_t$ is the **design vector** $(p \times m \times T)$  
    # `obs_intercept` $\equiv d_t$ is the **observation intercept** $(p \times T)$  
    # `obs_cov` $\equiv H_t$ is the **observation covariance matrix** $(p \times p \times T)$  
    # `transition` $\equiv T_t$ is the **transition matrix** $(m \times m \times T)$  
    # `state_intercept` $\equiv c_t$ is the **state intercept** $(m \times T)$  
    # `selection` $\equiv R_t$ is the **selection matrix** $(m \times r \times T)$  
    # `state_cov` $\equiv Q_t$ is the **state covariance matrix** $(r \times r \times T)$  
    # `selected_state_cov` $\equiv R Q_t R'$ is the **selected state covariance matrix** $(m \times m \times T)$  
    # `initial_state` $\equiv a_1$ is the **initial state mean** $(m \times 1)$  
    # `initial_state_cov` $\equiv P_1$ is the **initial state covariance matrix** $(m \times m)$
    #
    # With the exception of `obs`, these are *optionally* time-varying. If they are instead time-invariant,
    # then the dimension of length $T$ is instead of length $1$.
    #
    # *Note*: the initial vectors' notation 1-indexed as in Durbin and Koopman,
    # but in the recursions below it will be 0-indexed in the Python arrays.
    # 
    # *Old notation: y, -, mu, beta_tt_init, P_tt_init*
    cdef readonly np.complex128_t [::1,:] obs, obs_intercept, state_intercept
    cdef readonly np.complex128_t [:] initial_state
    cdef readonly np.complex128_t [::1,:] initial_state_cov
    # *Old notation: H, R, F, G, Q*, G Q* G'*
    cdef readonly np.complex128_t [::1,:,:] design, obs_cov, transition, selection, state_cov, selected_state_cov

    # `missing` is a $(p \times T)$ boolean matrix where a row is a $(p \times 1)$ vector
    # in which the $i$th position is $1$ if $y_{i,t}$ is to be considered a missing value.  
    # *Note:* This is created as the output of np.isnan(obs).
    cdef readonly int [::1,:] missing
    # `nmissing` is an `T \times 0` integer vector holding the number of *missing* observations
    # $p - p_t$
    cdef readonly int [:] nmissing

    # Flag for a time-invariant model, which requires that *all* of the
    # possibly time-varying arrays are time-invariant.
    cdef readonly int time_invariant

    # Flag for initialization.
    cdef readonly int initialized

    # Temporary arrays
    cdef np.complex128_t [::1,:] tmp

    # Pointers  
    # *Note*: These are not yet implemented to do anything in this base class
    # but are used in subclasses. Necessary to have them here due to problems
    # with redeclaring the model attribute of KalmanFilter children classes
    cdef np.complex128_t * _obs
    cdef np.complex128_t * _design
    cdef np.complex128_t * _obs_intercept
    cdef np.complex128_t * _obs_cov
    cdef np.complex128_t * _transition
    cdef np.complex128_t * _state_intercept
    cdef np.complex128_t * _selection
    cdef np.complex128_t * _state_cov
    cdef np.complex128_t * _selected_state_cov
    cdef np.complex128_t * _initial_state
    cdef np.complex128_t * _initial_state_cov

    # ### Initialize state space model
    # *Note*: The initial state and state covariance matrix must be provided.
    def __init__(self,
                 np.complex128_t [::1,:]   obs,
                 np.complex128_t [::1,:,:] design,
                 np.complex128_t [::1,:]   obs_intercept,
                 np.complex128_t [::1,:,:] obs_cov,
                 np.complex128_t [::1,:,:] transition,
                 np.complex128_t [::1,:]   state_intercept,
                 np.complex128_t [::1,:,:] selection,
                 np.complex128_t [::1,:,:] state_cov):

        # Local variables
        cdef:
            np.npy_intp dim1[1]
            np.npy_intp dim2[2]
            np.npy_intp dim3[3]

        # #### State space representation variables  
        # **Note**: these arrays share data with the versions defined in
        # Python and passed to this constructor, so if they are updated in
        # Python they will also be updated here.
        self.obs = obs
        self.design = design
        self.obs_intercept = obs_intercept
        self.obs_cov = obs_cov
        self.transition = transition
        self.state_intercept = state_intercept
        self.selection = selection
        self.state_cov = state_cov

        # Dimensions
        self.k_endog = obs.shape[0]
        self.k_states = selection.shape[0]
        self.k_posdef = selection.shape[1]
        self.nobs = obs.shape[1]

        # #### Validate matrix dimensions
        #
        # Make sure that the given state-space matrices have consistent sizes
        validate_matrix_shape('design', &self.design.shape[0],
                              self.k_endog, self.k_states, self.nobs)
        validate_vector_shape('observation intercept', &self.obs_intercept.shape[0],
                              self.k_endog, self.nobs)
        validate_matrix_shape('observation covariance matrix', &self.obs_cov.shape[0],
                              self.k_endog, self.k_endog, self.nobs)
        validate_matrix_shape('transition', &self.transition.shape[0],
                              self.k_states, self.k_states, self.nobs)
        validate_vector_shape('state intercept', &self.state_intercept.shape[0],
                              self.k_states, self.nobs)
        validate_matrix_shape('state covariance matrix', &self.state_cov.shape[0],
                              self.k_posdef, self.k_posdef, self.nobs)

        # Check for a time-invariant model
        self.time_invariant = (
            self.design.shape[2] == 1           and
            self.obs_intercept.shape[1] == 1    and
            self.obs_cov.shape[2] == 1          and
            self.transition.shape[2] == 1       and
            self.state_intercept.shape[1] == 1  and
            self.selection.shape[2] == 1        and
            self.state_cov.shape[2] == 1
        )

        # Set the flag for initialization to be false
        self.initialized = False

        # Allocate selected state covariance matrix
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = 1;
        # (we only allocate memory for time-varying array if necessary)
        if self.state_cov.shape[2] > 1 or self.selection.shape[2] > 1:
            dim3[2] = self.nobs
        self.selected_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_COMPLEX128, FORTRAN)

        # Handle missing data
        self.missing = np.array(np.isnan(obs), dtype=np.int32, order="F")
        self.nmissing = np.array(np.sum(self.missing, axis=0), dtype=np.int32)

        # Create the temporary array
        # Holds arrays of dimension $(m \times m)$
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.tmp = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)

    # ## Initialize: known values
    #
    # Initialize the filter with specific values, assumed to be known with
    # certainty or else as filled with parameters from a maximum likelihood
    # estimation run.
    def initialize_known(self, np.complex128_t [:] initial_state, np.complex128_t [::1,:] initial_state_cov):
        """
        initialize_known(initial_state, initial_state_cov)
        """
        validate_vector_shape('inital state', &initial_state.shape[0], self.k_states, None)
        validate_matrix_shape('initial state covariance', &initial_state_cov.shape[0], self.k_states, self.k_states, None)

        self.initial_state = initial_state
        self.initial_state_cov = initial_state_cov

        self.initialized = True

    # ## Initialize: approximate diffuse priors
    #
    # Durbin and Koopman note that this initialization should only be coupled
    # with the standard Kalman filter for "approximate exploratory work" and
    # can lead to "large rounding errors" (p. 125).
    # 
    # *Note:* see Durbin and Koopman section 5.6.1
    def initialize_approximate_diffuse(self, variance=1e2):
        """
        initialize_approximate_diffuse(variance=1e2)
        """
        cdef np.npy_intp dim[1]
        dim[0] = self.k_states
        self.initial_state = np.PyArray_ZEROS(1, dim, np.NPY_COMPLEX128, FORTRAN)
        self.initial_state_cov = np.eye(self.k_states, dtype=complex).T * variance

        self.initialized = True

    # ## Initialize: stationary process
    # *Note:* see Durbin and Koopman section 5.6.2
    # 
    # TODO improve efficiency with direct BLAS / LAPACK calls
    def initialize_stationary(self):
        """
        initialize_stationary()
        """
        cdef np.npy_intp dim[1]

        # Create selected state covariance matrix
        zselect_state_cov(self.k_states, self.k_posdef,
                                   &self.tmp[0,0],
                                   &self.selection[0,0,0],
                                   &self.state_cov[0,0,0],
                                   &self.selected_state_cov[0,0,0])

        from scipy.linalg import solve_discrete_lyapunov

        dim[0] = self.k_states
        self.initial_state = np.PyArray_ZEROS(1, dim, np.NPY_COMPLEX128, FORTRAN)
        self.initial_state_cov = solve_discrete_lyapunov(
            np.array(self.transition[:,:,0], dtype=complex),
            np.array(self.selected_state_cov[:,:,0], dtype=complex)
        ).T

        self.initialized = True

# ### Selected state covariance matrice
cdef int zselect_state_cov(int k_states, int k_posdef,
                                    np.complex128_t * tmp,
                                    np.complex128_t * selection,
                                    np.complex128_t * state_cov,
                                    np.complex128_t * selected_state_cov):
    cdef:
        np.complex128_t alpha = 1.0
        np.complex128_t beta = 0.0

    # Only need to do something if there is a state covariance matrix
    # (i.e k_posdof == 0)
    if k_posdef > 0:

        # #### Calculate selected state covariance matrix  
        # $Q_t^* = R_t Q_t R_t'$
        # 
        # Combine the selection matrix and the state covariance matrix to get
        # the simplified (but possibly singular) "selected" state covariance
        # matrix (see e.g. Durbin and Koopman p. 43)

        # `tmp0` array used here, dimension $(m \times r)$  

        # $\\#_0 = 1.0 * R_t Q_t$  
        # $(m \times r) = (m \times r) (r \times r)$
        zgemm("N", "N", &k_states, &k_posdef, &k_posdef,
              &alpha, selection, &k_states,
                      state_cov, &k_posdef,
              &beta, tmp, &k_states)
        # $Q_t^* = 1.0 * \\#_0 R_t'$  
        # $(m \times m) = (m \times r) (m \times r)'$
        zgemm("N", "T", &k_states, &k_states, &k_posdef,
              &alpha, tmp, &k_states,
                      selection, &k_states,
              &beta, selected_state_cov, &k_states)

# ## Kalman filter Routines
# 
# The following functions are the workhorse functions for the Kalman filter.
# They represent four distinct but very general phases of the Kalman filtering
# operations.
#
# Their argument is an object of class ?KalmanFilter, which is a stateful
# representation of the recursive filter. For this reason, the below functions
# work almost exclusively through *side-effects* and most return void.
# See the Kalman filter class documentation for further discussion.
#
# They are defined this way so that the actual filtering process can select
# whichever filter type is appropriate for the given time period. For example,
# in the case of state space models with non-stationary components, the filter
# should begin with the exact initial Kalman filter routines but after some
# number of time periods will transition to the conventional Kalman filter
# routines.
#
# Below, `<filter type>` will refer to one of the following:
#
# - `conventional` - the conventional Kalman filter
#
# Other filter types (e.g. `exact_initial`, `augmented`, etc.) may be added in
# the future.
# 
# `forecast_<filter type>` generates the forecast, forecast error $v_t$ and
# forecast error covariance matrix $F_t$  
# `updating_<filter type>` is the updating step of the Kalman filter, and
# generates the filtered state $a_{t|t}$ and covariance matrix $P_{t|t}$  
# `prediction_<filter type>` is the prediction step of the Kalman filter, and
# generates the predicted state $a_{t+1}$ and covariance matrix $P_{t+1}$.
# `loglikelihood_<filter type>` calculates the loglikelihood for $y_t$

# ### Missing Observation Conventional Kalman filter
#
# See Durbin and Koopman (2012) Chapter 4.10
#
# Here k_endog is the same as usual, but the design matrix and observation
# covariance matrix are enforced to be zero matrices, and the loglikelihood
# is defined to be zero.

cdef int zforecast_missing_conventional(zKalmanFilter kfilter):
    cdef int i, j
    cdef int inc = 1

    # #### Forecast for time t  
    # `forecast` $= Z_t a_t + d_t$
    # Just set to zeros, see below (this means if forecasts are required for
    # this part, they must be done in the wrappe)

    # #### Forecast error for time t  
    # It is undefined here, since obs is nan
    for i in range(kfilter.k_endog):
        kfilter._forecast[i] = 0
        kfilter._forecast_error[i] = 0

    # #### Forecast error covariance matrix for time t  
    # $F_t \equiv 0$
    for i in range(kfilter.k_endog):
        for j in range(kfilter.k_endog):
            kfilter._forecast_error_cov[j + i*kfilter.k_endog] = 0

cdef int zupdating_missing_conventional(zKalmanFilter kfilter):
    cdef int inc = 1

    # Simply copy over the input arrays ($a_t, P_t$) to the filtered arrays
    # ($a_{t|t}, P_{t|t}$)
    zcopy(&kfilter.k_states, kfilter._input_state, &inc, kfilter._filtered_state, &inc)
    zcopy(&kfilter.k_states2, kfilter._input_state_cov, &inc, kfilter._filtered_state_cov, &inc)

cdef np.complex128_t zinverse_missing_conventional(zKalmanFilter kfilter, np.complex128_t determinant)  except *:
    # Since the inverse of the forecast error covariance matrix is not
    # stored, we don't need to fill it (e.g. with NPY_NAN values). Instead,
    # just do a noop here and return a zero determinant ($|0|$).
    return 0.0

cdef np.complex128_t zloglikelihood_missing_conventional(zKalmanFilter kfilter, np.complex128_t determinant):
    return 0.0

# ### Conventional Kalman filter
#
# The following are the above routines as defined in the conventional Kalman
# filter.
#
# See Durbin and Koopman (2012) Chapter 4

cdef int zforecast_conventional(zKalmanFilter kfilter):

    # Constants
    cdef:
        int inc = 1, ld
        np.complex128_t alpha = 1.0
        np.complex128_t beta = 0.0
        np.complex128_t gamma = -1.0

    # #### Forecast for time t  
    # `forecast` $= Z_t a_t + d_t$
    # 
    # *Note*: $a_t$ is given from the initialization (for $t = 0$) or
    # from the previous iteration of the filter (for $t > 0$).

    # $\\# = d_t$
    zcopy(&kfilter.k_endog, kfilter._obs_intercept, &inc, kfilter._forecast, &inc)
    # `forecast` $= 1.0 * Z_t a_t + 1.0 * \\#$  
    # $(p \times 1) = (p \times m) (m \times 1) + (p \times 1)$
    zgemv("N", &kfilter.k_endog, &kfilter.k_states,
          &alpha, kfilter._design, &kfilter.k_endog,
                  kfilter._input_state, &inc,
          &alpha, kfilter._forecast, &inc)

    # #### Forecast error for time t  
    # `forecast_error` $\equiv v_t = y_t -$ `forecast`

    # $\\# = y_t$
    zcopy(&kfilter.k_endog, kfilter._obs, &inc, kfilter._forecast_error, &inc)
    # $v_t = -1.0 * $ `forecast` $ + \\#$
    # $(p \times 1) = (p \times 1) + (p \times 1)$
    zaxpy(&kfilter.k_endog, &gamma, kfilter._forecast, &inc, kfilter._forecast_error, &inc)

    # *Intermediate calculation* (used just below and then once more)  
    # `tmp1` array used here, dimension $(m \times p)$  
    # $\\#_1 = P_t Z_t'$  
    # $(m \times p) = (m \times m) (p \times m)'$
    zgemm("N", "T", &kfilter.k_states, &kfilter.k_endog, &kfilter.k_states,
          &alpha, kfilter._input_state_cov, &kfilter.k_states,
                  kfilter._design, &kfilter.k_endog,
          &beta, kfilter._tmp1, &kfilter.k_states)

    # #### Forecast error covariance matrix for time t  
    # $F_t \equiv Z_t P_t Z_t' + H_t$
    # 
    # *Note*: this and does nothing at all to `forecast_error_cov` if
    # converged == True
    if not kfilter.converged:
        # $\\# = H_t$
        zcopy(&kfilter.k_endog2, kfilter._obs_cov, &inc, kfilter._forecast_error_cov, &inc)

        # $F_t = 1.0 * Z_t \\#_1 + 1.0 * \\#$
        zgemm("N", "N", &kfilter.k_endog, &kfilter.k_endog, &kfilter.k_states,
              &alpha, kfilter._design, &kfilter.k_endog,
                     kfilter._tmp1, &kfilter.k_states,
              &alpha, kfilter._forecast_error_cov, &kfilter.k_endog)

    return 0

cdef int zupdating_conventional(zKalmanFilter kfilter):
    # Constants
    cdef:
        int inc = 1
        np.complex128_t alpha = 1.0
        np.complex128_t beta = 0.0
        np.complex128_t gamma = -1.0
    
    # #### Filtered state for time t
    # $a_{t|t} = a_t + P_t Z_t' F_t^{-1} v_t$  
    # $a_{t|t} = 1.0 * \\#_1 \\#_2 + 1.0 a_t$
    zcopy(&kfilter.k_states, kfilter._input_state, &inc, kfilter._filtered_state, &inc)
    zgemv("N", &kfilter.k_states, &kfilter.k_endog,
          &alpha, kfilter._tmp1, &kfilter.k_states,
                  kfilter._tmp2, &inc,
          &alpha, kfilter._filtered_state, &inc)

    # #### Filtered state covariance for time t
    # $P_{t|t} = P_t - P_t Z_t' F_t^{-1} Z_t P_t$  
    # $P_{t|t} = P_t - \\#_1 \\#_3 P_t$  
    # 
    # *Note*: this and does nothing at all to `filtered_state_cov` if
    # converged == True
    if not kfilter.converged:
        zcopy(&kfilter.k_states2, kfilter._input_state_cov, &inc, kfilter._filtered_state_cov, &inc)

        # `tmp0` array used here, dimension $(m \times m)$  
        # $\\#_0 = 1.0 * \\#_1 \\#_3$  
        # $(m \times m) = (m \times p) (p \times m)$
        zgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_endog,
              &alpha, kfilter._tmp1, &kfilter.k_states,
                      kfilter._tmp3, &kfilter.k_endog,
              &beta, kfilter._tmp0, &kfilter.k_states)

        # $P_{t|t} = - 1.0 * \\# P_t + 1.0 * P_t$  
        # $(m \times m) = (m \times m) (m \times m) + (m \times m)$
        zgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &gamma, kfilter._tmp0, &kfilter.k_states,
                      kfilter._input_state_cov, &kfilter.k_states,
              &alpha, kfilter._filtered_state_cov, &kfilter.k_states)

    return 0

cdef int zprediction_conventional(zKalmanFilter kfilter):

    # Constants
    cdef:
        int inc = 1
        np.complex128_t alpha = 1.0
        np.complex128_t beta = 0.0
        np.complex128_t gamma = -1.0

    # #### Predicted state for time t+1
    # $a_{t+1} = T_t a_{t|t} + c_t$
    zcopy(&kfilter.k_states, kfilter._state_intercept, &inc, kfilter._predicted_state, &inc)
    zgemv("N", &kfilter.k_states, &kfilter.k_states,
          &alpha, kfilter._transition, &kfilter.k_states,
                  kfilter._filtered_state, &inc,
          &alpha, kfilter._predicted_state, &inc)

    # #### Predicted state covariance matrix for time t+1
    # $P_{t+1} = T_t P_{t|t} T_t' + Q_t^*$
    #
    # *Note*: this and does nothing at all to `predicted_state_cov` if
    # converged == True
    if not kfilter.converged:
        zcopy(&kfilter.k_states2, kfilter._selected_state_cov, &inc, kfilter._predicted_state_cov, &inc)
        # `tmp0` array used here, dimension $(m \times m)$  

        # $\\#_0 = T_t P_{t|t} $

        # $(m \times m) = (m \times m) (m \times m)$
        zgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &alpha, kfilter._transition, &kfilter.k_states,
                      kfilter._filtered_state_cov, &kfilter.k_states,
              &beta, kfilter._tmp0, &kfilter.k_states)
        # $P_{t+1} = 1.0 \\#_0 T_t' + 1.0 \\#$  
        # $(m \times m) = (m \times m) (m \times m) + (m \times m)$
        zgemm("N", "T", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &alpha, kfilter._tmp0, &kfilter.k_states,
                      kfilter._transition, &kfilter.k_states,
              &alpha, kfilter._predicted_state_cov, &kfilter.k_states)

    return 0


cdef np.complex128_t zloglikelihood_conventional(zKalmanFilter kfilter, np.complex128_t determinant):
    # Constants
    cdef:
        np.complex128_t loglikelihood
        int inc = 1
        np.complex128_t alpha = 1.0
        np.complex128_t beta = 0.0

    loglikelihood = -0.5*(kfilter.k_endog*zlog(2*NPY_PI) + zlog(determinant))

    zgemv("N", &inc, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error, &inc,
                           kfilter._tmp2, &inc,
                   &beta, kfilter._tmp0, &inc)
    loglikelihood = loglikelihood - 0.5 * kfilter._tmp0[0]

    return loglikelihood

# ## Forecast error covariance inversion
#
# The following are routines that can calculate the inverse of the forecast
# error covariance matrix (defined in `forecast_<filter type>`).
#
# These routines are aware of the possibility that the Kalman filter may have
# converged to a steady state, in which case they do not need to perform the
# inversion or calculate the determinant.

cdef np.complex128_t zinverse_univariate(zKalmanFilter kfilter, np.complex128_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using simple division
    in the case that the observations are univariate.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    # #### Intermediate values
    cdef:
        int inc = 1
        np.complex128_t scalar

    # Take the inverse of the forecast error covariance matrix
    if not kfilter.converged:
        determinant = kfilter._forecast_error_cov[0]
    try:
        scalar = 1.0 / kfilter._forecast_error_cov[0]
    except:
        raise np.linalg.LinAlgError('Non-positive-definite forecast error'
                                   ' covariance matrix encountered at'
                                   ' period %d' % kfilter.t)
    kfilter._tmp2[0] = scalar * kfilter._forecast_error[0]
    zcopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    zscal(&kfilter.k_endogstates, &scalar, kfilter._tmp3, &inc)

    return determinant

cdef np.complex128_t zfactorize_cholesky(zKalmanFilter kfilter, np.complex128_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using a Cholesky
    decomposition. Called by either of the `solve_cholesky` or
    `invert_cholesky` routines.

    Requires a positive definite matrix, but is faster than an LU
    decomposition.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int inc = 1
        int info
        int i

    if not kfilter.converged:
        zcopy(&kfilter.k_endog2, kfilter._forecast_error_cov, &inc, kfilter._forecast_error_fac, &inc)
        zpotrf("U", &kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog, &info)

        if info < 0:
            raise np.linalg.LinAlgError('Illegal value in forecast error'
                                        ' covariance matrix encountered at'
                                        ' period %d' % kfilter.t)
        if info > 0:
            raise np.linalg.LinAlgError('Non-positive-definite forecast error'
                                       ' covariance matrix encountered at'
                                       ' period %d' % kfilter.t)

        # Calculate the determinant (just the squared product of the
        # diagonals, in the Cholesky decomposition case)
        determinant = 1.0
        for i in range(kfilter.k_endog):
            determinant = determinant * kfilter.forecast_error_fac[i, i]
        determinant = determinant**2

    return determinant

cdef np.complex128_t zfactorize_lu(zKalmanFilter kfilter, np.complex128_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using an LU
    decomposition. Called by either of the `solve_lu` or `invert_lu`
    routines.

    Is slower than a Cholesky decomposition, but does not require a
    positive definite matrix.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int inc = 1
        int info
        int i

    if not kfilter.converged:
        # Perform LU decomposition into `forecast_error_fac`
        zcopy(&kfilter.k_endog2, kfilter._forecast_error_cov, &inc, kfilter._forecast_error_fac, &inc)
        
        zgetrf(&kfilter.k_endog, &kfilter.k_endog,
                        kfilter._forecast_error_fac, &kfilter.k_endog,
                        kfilter._forecast_error_ipiv, &info)

        if info < 0:
            raise np.linalg.LinAlgError('Illegal value in forecast error'
                                        ' covariance matrix encountered at'
                                        ' period %d' % kfilter.t)
        if info > 0:
            raise np.linalg.LinAlgError('Singular forecast error covariance'
                                        ' matrix encountered at period %d' %
                                        kfilter.t)

        # Calculate the determinant (product of the diagonals, but with
        # sign modifications according to the permutation matrix)    
        determinant = 1
        for i in range(kfilter.k_endog):
            if not kfilter._forecast_error_ipiv[i] == i+1:
                determinant *= -1*kfilter.forecast_error_fac[i, i]
            else:
                determinant *= kfilter.forecast_error_fac[i, i]

    return determinant

cdef np.complex128_t zinverse_cholesky(zKalmanFilter kfilter, np.complex128_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        int i, j
        np.complex128_t alpha = 1.0
        np.complex128_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = zfactorize_cholesky(kfilter, determinant)

        # Continue taking the inverse
        zpotri("U", &kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog, &info)

        # ?potri only fills in the upper triangle of the symmetric array, and
        # since the ?symm and ?symv routines are not available as of scipy
        # 0.11.0, we can't use them, so we must fill in the lower triangle
        # by hand
        for i in range(kfilter.k_endog):
            for j in range(i):
                kfilter.forecast_error_fac[i,j] = kfilter.forecast_error_fac[j,i]


    # Get `tmp2` and `tmp3` via matrix multiplications

    # `tmp2` array used here, dimension $(p \times 1)$  
    # $\\#_2 = F_t^{-1} v_t$  
    #zsymv("U", &kfilter.k_endog, &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
    #               kfilter._forecast_error, &inc, &beta, kfilter._tmp2, &inc)
    zgemv("N", &kfilter.k_endog, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._forecast_error, &inc,
                   &beta, kfilter._tmp2, &inc)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $\\#_3 = F_t^{-1} Z_t$
    #zsymm("L", "U", &kfilter.k_endog, &kfilter.k_states,
    #               &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
    #                       kfilter._design, &kfilter.k_endog,
    #               &beta, kfilter._tmp3, &kfilter.k_endog)
    zgemm("N", "N", &kfilter.k_endog, &kfilter.k_states, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._design, &kfilter.k_endog,
                   &beta, kfilter._tmp3, &kfilter.k_endog)

    return determinant

cdef np.complex128_t zinverse_lu(zKalmanFilter kfilter, np.complex128_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        np.complex128_t alpha = 1.0
        np.complex128_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = zfactorize_lu(kfilter, determinant)

        # Continue taking the inverse
        zgetri(&kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog,
               kfilter._forecast_error_ipiv, kfilter._forecast_error_work, &kfilter.ldwork, &info)

    # Get `tmp2` and `tmp3` via matrix multiplications

    # `tmp2` array used here, dimension $(p \times 1)$  
    # $\\#_2 = F_t^{-1} v_t$  
    zgemv("N", &kfilter.k_endog, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._forecast_error, &inc,
                   &beta, kfilter._tmp2, &inc)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $\\#_3 = F_t^{-1} Z_t$
    zgemm("N", "N", &kfilter.k_endog, &kfilter.k_states, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._design, &kfilter.k_endog,
                   &beta, kfilter._tmp3, &kfilter.k_endog)

    return determinant

cdef np.complex128_t zsolve_cholesky(zKalmanFilter kfilter, np.complex128_t determinant) except *:
    """
    solve_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = zfactorize_cholesky(kfilter, determinant)

    # Solve the linear systems  
    # `tmp2` array used here, dimension $(p \times 1)$  
    # $F_t \\#_2 = v_t$  
    zcopy(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)
    zpotrs("U", &kfilter.k_endog, &inc, kfilter._forecast_error_fac, &kfilter.k_endog, kfilter._tmp2, &kfilter.k_endog, &info)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $F_t \\#_3 = Z_t$
    zcopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    zpotrs("U", &kfilter.k_endog, &kfilter.k_states, kfilter._forecast_error_fac, &kfilter.k_endog, kfilter._tmp3, &kfilter.k_endog, &info)

    return determinant

cdef np.complex128_t zsolve_lu(zKalmanFilter kfilter, np.complex128_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        np.complex128_t alpha = 1.0
        np.complex128_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = zfactorize_lu(kfilter, determinant)

    # Solve the linear systems  
    # `tmp2` array used here, dimension $(p \times 1)$  
    # $F_t \\#_2 = v_t$  
    zcopy(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)
    zgetrs("N", &kfilter.k_endog, &inc, kfilter._forecast_error_fac, &kfilter.k_endog,
                    kfilter._forecast_error_ipiv, kfilter._tmp2, &kfilter.k_endog, &info)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $F_t \\#_3 = Z_t$
    zcopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    zgetrs("N", &kfilter.k_endog, &kfilter.k_states, kfilter._forecast_error_fac, &kfilter.k_endog,
                    kfilter._forecast_error_ipiv, kfilter._tmp3, &kfilter.k_endog, &info)

    return determinant


# ## Kalman filter

cdef class zKalmanFilter(object):
    """
    zKalmanFilter(model, filter=FILTER_CONVENTIONAL, inversion_method=INVERT_UNIVARIATE | SOLVE_CHOLESKY, stability_method=STABILITY_FORCE_SYMMETRY, tolerance=1e-19)

    A representation of the Kalman filter recursions.

    While the filter is mathematically represented as a recursion, it is here
    translated into Python as a stateful iterator.

    Because there are actually several types of Kalman filter depending on the
    state space model of interest, this class only handles the *iteration*
    aspect of filtering, and delegates the actual operations to four general
    workhorse routines, which can be implemented separately for each type of
    Kalman filter.

    In order to maintain a consistent interface, and because these four general
    routines may be quite different across filter types, their argument is only
    the stateful ?KalmanFilter object. Furthermore, in order to allow the
    different types of filter to substitute alternate matrices, this class
    defines a set of pointers to the various state space arrays and the
    filtering output arrays.

    For example, handling missing observations requires not only substituting
    `obs`, `design`, and `obs_cov` matrices, but the new matrices actually have
    different dimensions than the originals. This can be flexibly accomodated
    simply by replacing e.g. the `obs` pointer to the substituted `obs` array
    and replacing `k_endog` for that iteration. Then in the next iteration, when
    the `obs` vector may be missing different elements (or none at all), it can
    again be redefined.

    Each iteration of the filter (see `__next__`) proceeds in a number of
    steps.

    `initialize_object_pointers` initializes pointers to current-iteration
    objects (i.e. the state space arrays and filter output arrays).  

    `initialize_function_pointers` initializes pointers to the appropriate
    Kalman filtering routines (i.e. `forecast_conventional` or
    `forecast_exact_initial`, etc.).  

    `select_arrays` converts the base arrays into "selected" arrays using
    selection matrices. In particular, it handles the state covariance matrix
    and redefined matrices based on missing values.  

    `post_convergence` handles copying arrays from time $t-1$ to time $t$ when
    the Kalman filter has converged and they don't need to be re-calculated.  

    `forecasting` calls the Kalman filter `forcasting_<filter type>` routine

    `inversion` calls the appropriate function to invert the forecast error
    covariance matrix.  

    `updating` calls the Kalman filter `updating_<filter type>` routine

    `loglikelihood` calls the Kalman filter `loglikelihood_<filter type>` routine

    `prediction` calls the Kalman filter `prediction_<filter type>` routine

    `numerical_stability` performs end-of-iteration tasks to improve the numerical
    stability of the filter 

    `check_convergence` checks for convergence of the filter to steady-state.
    """

    # ### Statespace model
    cdef readonly zStatespace model

    # ### Filter parameters
    # Holds the time-iteration state of the filter  
    # *Note*: must be changed using the `seek` method
    cdef readonly int t
    # Holds the tolerance parameter for convergence
    cdef public np.float64_t tolerance
    # Holds the convergence to steady-state status of the filter
    # *Note*: is by default reset each time `seek` is called
    cdef readonly int converged
    cdef readonly int period_converged
    # Holds whether or not the model is time-invariant
    # *Note*: is by default reset each time `seek` is called
    cdef readonly int time_invariant
    # The Kalman filter procedure to use  
    cdef public int filter_method
    # The method by which the terms using the inverse of the forecast
    # error covariance matrix are solved.
    cdef public int inversion_method
    # Methods to improve numerical stability
    cdef public int stability_method
    # Whether or not to conserve memory
    # If True, only stores filtered states and covariance matrices
    cdef readonly int conserve_memory
    # If conserving loglikelihood, the number of periods to "burn"
    # before starting to record the loglikelihood
    cdef readonly int loglikelihood_burn

    # ### Kalman filter properties

    # `loglikelihood` $\equiv \log p(y_t | Y_{t-1})$
    cdef readonly np.complex128_t [:] loglikelihood

    # `filtered_state` $\equiv a_{t|t} = E(\alpha_t | Y_t)$ is the **filtered estimator** of the state $(m \times T)$  
    # `predicted_state` $\equiv a_{t+1} = E(\alpha_{t+1} | Y_t)$ is the **one-step ahead predictor** of the state $(m \times T-1)$  
    # `forecast` $\equiv E(y_t|Y_{t-1})$ is the **forecast** of the next observation $(p \times T)$   
    # `forecast_error` $\equiv v_t = y_t - E(y_t|Y_{t-1})$ is the **one-step ahead forecast error** of the next observation $(p \times T)$  
    # 
    # *Note*: Actual values in `filtered_state` will be from 1 to `nobs`+1. Actual
    # values in `predicted_state` will be from 0 to `nobs`+1 because the initialization
    # is copied over to the zeroth entry, and similar for the covariances, below.
    #
    # *Old notation: beta_tt, beta_tt1, y_tt1, eta_tt1*
    cdef readonly np.complex128_t [::1,:] filtered_state, predicted_state, forecast, forecast_error

    # `filtered_state_cov` $\equiv P_{t|t} = Var(\alpha_t | Y_t)$ is the **filtered state covariance matrix** $(m \times m \times T)$  
    # `predicted_state_cov` $\equiv P_{t+1} = Var(\alpha_{t+1} | Y_t)$ is the **predicted state covariance matrix** $(m \times m \times T)$  
    # `forecast_error_cov` $\equiv F_t = Var(v_t | Y_{t-1})$ is the **forecast error covariance matrix** $(p \times p \times T)$  
    # 
    # *Old notation: P_tt, P_tt1, f_tt1*
    cdef readonly np.complex128_t [::1,:,:] filtered_state_cov, predicted_state_cov, forecast_error_cov

    # ### Steady State Values
    # These matrices are used to hold the converged matrices after the Kalman
    # filter has reached steady-state
    cdef readonly np.complex128_t [::1,:] converged_forecast_error_cov
    cdef readonly np.complex128_t [::1,:] converged_filtered_state_cov
    cdef readonly np.complex128_t [::1,:] converged_predicted_state_cov
    cdef readonly np.complex128_t converged_determinant

    # ### Temporary arrays
    # These matrices are used to temporarily hold selected observation vectors,
    # design matrices, and observation covariance matrices in the case of
    # missing data.  
    cdef readonly np.complex128_t [:] selected_obs
    # The following are contiguous memory segments which are then used to
    # store the data in the above matrices.
    cdef readonly np.complex128_t [:] selected_design
    cdef readonly np.complex128_t [:] selected_obs_cov
    # `forecast_error_fac` is a forecast error covariance matrix **factorization** $(p \times p)$.
    # Depending on the method for handling the inverse of the forecast error covariance matrix, it may be:
    # - a Cholesky factorization if `cholesky_solve` is used
    # - an inverse calculated via Cholesky factorization if `cholesky_inverse` is used
    # - an LU factorization if `lu_solve` is used
    # - an inverse calculated via LU factorization if `lu_inverse` is used
    cdef readonly np.complex128_t [::1,:] forecast_error_fac
    # `forecast_error_ipiv` holds pivot indices if an LU decomposition is used
    cdef readonly int [:] forecast_error_ipiv
    # `forecast_error_work` is a work array for matrix inversion if an LU
    # decomposition is used
    cdef readonly np.complex128_t [::1,:] forecast_error_work
    # These hold the memory allocations of the unnamed temporary arrays
    cdef readonly np.complex128_t [::1,:] tmp0, tmp1, tmp3
    cdef readonly np.complex128_t [:] tmp2

    # Holds the determinant across calculations (this is done because after
    # convergence, it doesn't need to be re-calculated anymore)
    cdef readonly np.complex128_t determinant

    # ### Pointers to current-iteration arrays
    cdef np.complex128_t * _obs
    cdef np.complex128_t * _design
    cdef np.complex128_t * _obs_intercept
    cdef np.complex128_t * _obs_cov
    cdef np.complex128_t * _transition
    cdef np.complex128_t * _state_intercept
    cdef np.complex128_t * _selection
    cdef np.complex128_t * _state_cov
    cdef np.complex128_t * _selected_state_cov
    cdef np.complex128_t * _initial_state
    cdef np.complex128_t * _initial_state_cov

    cdef np.complex128_t * _input_state
    cdef np.complex128_t * _input_state_cov

    cdef np.complex128_t * _forecast
    cdef np.complex128_t * _forecast_error
    cdef np.complex128_t * _forecast_error_cov
    cdef np.complex128_t * _filtered_state
    cdef np.complex128_t * _filtered_state_cov
    cdef np.complex128_t * _predicted_state
    cdef np.complex128_t * _predicted_state_cov

    cdef np.complex128_t * _converged_forecast_error_cov
    cdef np.complex128_t * _converged_filtered_state_cov
    cdef np.complex128_t * _converged_predicted_state_cov

    cdef np.complex128_t * _forecast_error_fac
    cdef int * _forecast_error_ipiv
    cdef np.complex128_t * _forecast_error_work

    cdef np.complex128_t * _tmp0
    cdef np.complex128_t * _tmp1
    cdef np.complex128_t * _tmp2
    cdef np.complex128_t * _tmp3

    # ### Pointers to current-iteration Kalman filtering functions
    cdef int (*forecasting)(
        zKalmanFilter
    )
    cdef np.complex128_t (*inversion)(
        zKalmanFilter, np.complex128_t
    ) except *
    cdef int (*updating)(
        zKalmanFilter
    )
    cdef np.complex128_t (*calculate_loglikelihood)(
        zKalmanFilter, np.complex128_t
    )
    cdef int (*prediction)(
        zKalmanFilter
    )

    # ### Define some constants
    cdef readonly int k_endog, k_states, k_posdef, k_endog2, k_states2, k_endogstates, ldwork
    
    def __init__(self,
                 zStatespace model,
                 int filter_method=FILTER_CONVENTIONAL,
                 int inversion_method=INVERT_UNIVARIATE | SOLVE_CHOLESKY,
                 int stability_method=STABILITY_FORCE_SYMMETRY,
                 int conserve_memory=MEMORY_STORE_ALL,
                 np.float64_t tolerance=1e-19,
                 int loglikelihood_burn=0):
        # Local variables
        cdef:
            np.npy_intp dim1[1]
            np.npy_intp dim2[2]
            np.npy_intp dim3[3]
        cdef int storage

        # Save the model
        self.model = model

        # Initialize filter parameters
        self.tolerance = tolerance
        if not filter_method == FILTER_CONVENTIONAL:
            raise NotImplementedError("Only the conventional Kalman filter is currently implemented")
        self.filter_method = filter_method
        self.inversion_method = inversion_method
        self.stability_method = stability_method
        self.conserve_memory = conserve_memory
        self.loglikelihood_burn = loglikelihood_burn

        # Initialize the constant values
        self.time_invariant = self.model.time_invariant
        self.k_endog = self.model.k_endog
        self.k_states = self.model.k_states
        self.k_posdef = self.model.k_posdef
        self.k_endog2 = self.model.k_endog**2
        self.k_states2 = self.model.k_states**2
        self.k_endogstates = self.model.k_endog * self.model.k_states
        # TODO replace with optimal work array size
        self.ldwork = self.model.k_endog

        # #### Allocate arrays for calculations

        # Arrays for Kalman filter output

        # Forecast
        if self.conserve_memory & MEMORY_NO_FORECAST:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_endog; dim2[1] = storage;
        self.forecast = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        self.forecast_error = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        dim3[0] = self.k_endog; dim3[1] = self.k_endog; dim3[2] = storage;
        self.forecast_error_cov = np.PyArray_ZEROS(3, dim3, np.NPY_COMPLEX128, FORTRAN)

        # Filtered
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_states; dim2[1] = storage;
        self.filtered_state = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = storage;
        self.filtered_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_COMPLEX128, FORTRAN)

        # Predicted
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_states; dim2[1] = storage+1;
        self.predicted_state = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = storage+1;
        self.predicted_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_COMPLEX128, FORTRAN)

        # Likelihood
        if self.conserve_memory & MEMORY_NO_LIKELIHOOD > 0:
            storage = 1
        else:
            storage = self.model.nobs
        dim1[0] = storage
        self.loglikelihood = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX128, FORTRAN)

        # Converged matrices
        dim2[0] = self.k_endog; dim2[1] = self.k_endog;
        self.converged_forecast_error_cov = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        self._converged_forecast_error_cov = &self.converged_forecast_error_cov[0,0]
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.converged_filtered_state_cov = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        self._converged_filtered_state_cov = &self.converged_filtered_state_cov[0,0]
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.converged_predicted_state_cov = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        self._converged_predicted_state_cov = &self.converged_predicted_state_cov[0,0]

        # #### Arrays for temporary calculations
        # *Note*: in math notation below, a $\\#$ will represent a generic
        # temporary array, and a $\\#_i$ will represent a named temporary array.

        # Arrays related to matrix factorizations / inverses
        dim2[0] = self.k_endog; dim2[1] = self.k_endog;
        self.forecast_error_fac = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        self._forecast_error_fac = &self.forecast_error_fac[0,0]
        dim2[0] = self.ldwork; dim2[1] = self.ldwork;
        self.forecast_error_work = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        self._forecast_error_work = &self.forecast_error_work[0,0]
        dim1[0] = self.k_endog;
        self.forecast_error_ipiv = np.PyArray_ZEROS(1, dim1, np.NPY_INT, FORTRAN)
        self._forecast_error_ipiv = &self.forecast_error_ipiv[0]

        # Holds arrays of dimension $(m \times m)$ and $(m \times r)$
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.tmp0 = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        self._tmp0 = &self.tmp0[0, 0]

        # Holds arrays of dimension $(m \times p)$
        dim2[0] = self.k_states; dim2[1] = self.k_endog;
        self.tmp1 = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        self._tmp1 = &self.tmp1[0, 0]

        # Holds arrays of dimension $(p \times 1)$
        dim1[0] = self.k_endog;
        self.tmp2 = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX128, FORTRAN)
        self._tmp2 = &self.tmp2[0]

        # Holds arrays of dimension $(p \times m)$
        dim2[0] = self.k_endog; dim2[1] = self.k_states;
        self.tmp3 = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX128, FORTRAN)
        self._tmp3 = &self.tmp3[0, 0]

        # Arrays for missing data
        dim1[0] = self.k_endog;
        self.selected_obs = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX128, FORTRAN)
        dim1[0] = self.k_endog * self.k_states;
        self.selected_design = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX128, FORTRAN)
        dim1[0] = self.k_endog2;
        self.selected_obs_cov = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX128, FORTRAN)

        # Initialize time and convergence status
        self.t = 0
        self.converged = 0
        self.period_converged = 0

    cpdef set_filter_method(self, int filter_method, int force_reset=True):
        """
        set_filter_method(self, filter_method, force_reset=True)

        Change the filter method.
        """
        self.filter_method = filter_method

    cpdef seek(self, unsigned int t, int reset_convergence = True):
        """
        seek(self, t, reset_convergence = True)

        Change the time-state of the filter

        Is usually called to reset the filter to the beginning.
        """
        if t >= self.model.nobs:
            raise IndexError("Observation index out of range")
        self.t = t

        if reset_convergence:
            self.converged = 0
            self.period_converged = 0

    def __iter__(self):
        return self

    def __call__(self):
        """
        Iterate the filter across the entire set of observations.
        """
        cdef int i

        self.seek(0, True)
        for i in range(self.model.nobs):
            next(self)

    def __next__(self):
        """
        Perform an iteration of the Kalman filter
        """

        # Get time subscript, and stop the iterator if at the end
        if not self.t < self.model.nobs:
            raise StopIteration

        # Initialize pointers to current-iteration objects
        self.initialize_statespace_object_pointers()
        self.initialize_filter_object_pointers()

        # Initialize pointers to appropriate Kalman filtering functions
        self.initialize_function_pointers()

        # Convert base arrays into "selected" arrays  
        # - State covariance matrix? $Q_t \to R_t Q_t R_t`$
        # - Missing values: $y_t \to W_t y_t$, $Z_t \to W_t Z_t$, $H_t \to W_t H_t$
        self.select_state_cov()
        self.select_missing()

        # Post-convergence: copy previous iteration arrays
        self.post_convergence()

        # Form forecasts
        self.forecasting(self)

        # Perform `forecast_error_cov` inversion (or decomposition)
        self.determinant = self.inversion(self, self.determinant)

        # Updating step
        self.updating(self)

        # Retrieve the loglikelihood
        if self.conserve_memory & MEMORY_NO_LIKELIHOOD > 0:
            if self.t == 0:
                self.loglikelihood[0] = 0
            if self.t >= self.loglikelihood_burn:
                self.loglikelihood[0] = self.loglikelihood[0] + self.calculate_loglikelihood(
                    self, self.determinant
                )
        else:
            self.loglikelihood[self.t] = self.calculate_loglikelihood(
                self, self.determinant
            )

        # Prediction step
        self.prediction(self)

        # Aids to numerical stability
        self.numerical_stability()

        # Check for convergence
        self.check_convergence()

        # If conserving memory, migrate storage: t->t-1, t+1->t
        self.migrate_storage()

        # Advance the time
        self.t += 1

    cdef void initialize_statespace_object_pointers(self) except *:
        cdef:
            int t = self.t
        # Indices for possibly time-varying arrays
        cdef:
            int design_t = 0
            int obs_intercept_t = 0
            int obs_cov_t = 0
            int transition_t = 0
            int state_intercept_t = 0
            int selection_t = 0
            int state_cov_t = 0

        # Get indices for possibly time-varying arrays
        if not self.model.time_invariant:
            if self.model.design.shape[2] > 1:             design_t = t
            if self.model.obs_intercept.shape[1] > 1:      obs_intercept_t = t
            if self.model.obs_cov.shape[2] > 1:            obs_cov_t = t
            if self.model.transition.shape[2] > 1:         transition_t = t
            if self.model.state_intercept.shape[1] > 1:    state_intercept_t = t
            if self.model.selection.shape[2] > 1:          selection_t = t
            if self.model.state_cov.shape[2] > 1:          state_cov_t = t

        # Initialize object-level pointers to statespace arrays
        self._obs = &self.model.obs[0, t]
        self._design = &self.model.design[0, 0, design_t]
        self._obs_intercept = &self.model.obs_intercept[0, obs_intercept_t]
        self._obs_cov = &self.model.obs_cov[0, 0, obs_cov_t]
        self._transition = &self.model.transition[0, 0, transition_t]
        self._state_intercept = &self.model.state_intercept[0, state_intercept_t]
        self._selection = &self.model.selection[0, 0, selection_t]
        self._state_cov = &self.model.state_cov[0, 0, state_cov_t]

        # Initialize object-level pointers to initialization
        if not self.model.initialized:
            raise RuntimeError("Statespace model not initialized.")
        self._initial_state = &self.model.initial_state[0]
        self._initial_state_cov = &self.model.initial_state_cov[0,0]

    cdef void initialize_filter_object_pointers(self):
        cdef:
            int t = self.t
            int inc = 1
        # Indices for arrays that may or may not be stored completely
        cdef:
            int forecast_t = t
            int filtered_t = t
            int predicted_t = t
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            forecast_t = 1
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            filtered_t = 1
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            predicted_t = 1

        # Initialize object-level pointers to input arrays
        self._input_state = &self.predicted_state[0, predicted_t]
        self._input_state_cov = &self.predicted_state_cov[0, 0, predicted_t]

        # Copy initialization arrays to input arrays if we're starting the
        # filter
        if t == 0:
            # `predicted_state[:,0]` $= a_1 =$ `initial_state`  
            # `predicted_state_cov[:,:,0]` $= P_1 =$ `initial_state_cov`  
            zcopy(&self.k_states, self._initial_state, &inc, self._input_state, &inc)
            zcopy(&self.k_states2, self._initial_state_cov, &inc, self._input_state_cov, &inc)

        # Initialize object-level pointers to output arrays
        self._forecast = &self.forecast[0, forecast_t]
        self._forecast_error = &self.forecast_error[0, forecast_t]
        self._forecast_error_cov = &self.forecast_error_cov[0, 0, forecast_t]

        self._filtered_state = &self.filtered_state[0, filtered_t]
        self._filtered_state_cov = &self.filtered_state_cov[0, 0, filtered_t]

        self._predicted_state = &self.predicted_state[0, predicted_t+1]
        self._predicted_state_cov = &self.predicted_state_cov[0, 0, predicted_t+1]

    cdef void initialize_function_pointers(self) except *:
        if self.filter_method & FILTER_CONVENTIONAL:
            self.forecasting = zforecast_conventional

            if self.inversion_method & INVERT_UNIVARIATE and self.k_endog == 1:
                self.inversion = zinverse_univariate
            elif self.inversion_method & SOLVE_CHOLESKY:
                self.inversion = zsolve_cholesky
            elif self.inversion_method & SOLVE_LU:
                self.inversion = zsolve_lu
            elif self.inversion_method & INVERT_CHOLESKY:
                self.inversion = zinverse_cholesky
            elif self.inversion_method & INVERT_LU:
                self.inversion = zinverse_lu
            else:
                raise NotImplementedError("Invalid inversion method")

            self.updating = zupdating_conventional
            self.calculate_loglikelihood = zloglikelihood_conventional
            self.prediction = zprediction_conventional

        else:
            raise NotImplementedError("Invalid filtering method")

    cdef void select_state_cov(self):
        cdef int selected_state_cov_t = 0

        # ### Get selected state covariance matrix
        if self.t == 0 or self.model.selected_state_cov.shape[2] > 1:
            selected_state_cov_t = self.t
            self._selected_state_cov = &self.model.selected_state_cov[0, 0, selected_state_cov_t]

            zselect_state_cov(self.k_states, self.k_posdef,
                                       self._tmp0,
                                       self._selection,
                                       self._state_cov,
                                       self._selected_state_cov)
        else:
            self._selected_state_cov = &self.model.selected_state_cov[0, 0, 0]

    cdef void select_missing(self):
        # ### Perform missing selections
        # In Durbin and Koopman (2012), these are represented as matrix
        # multiplications, i.e. $Z_t^* = W_t Z_t$ where $W_t$ is a row
        # selection matrix (it contains a subset of rows of the identity
        # matrix).
        #
        # It's more efficient, though, to just copy over the data directly,
        # which is what is done here. Note that the `selected_*` arrays are
        # defined as single-dimensional, so the assignment indexes below are
        # set such that the arrays can be interpreted by the BLAS and LAPACK
        # functions as two-dimensional, column-major arrays.
        #
        # In the case that all data is missing (e.g. this is what happens in
        # forecasting), we actually set don't change the dimension, but we set
        # the design matrix to the zeros array.
        if self.model.nmissing[self.t] == self.model.k_endog:
            self._select_missing_entire_obs()
        elif self.model.nmissing[self.t] > 0:
            self._select_missing_partial_obs()
        else:
            # Reset dimensions
            self.k_endog = self.model.k_endog
            self.k_endog2 = self.k_endog**2
            self.k_endogstates = self.k_endog * self.k_states

    cdef void _select_missing_entire_obs(self):
        cdef:
            int i, j
        # Mark as not converged so that it does not inappropriately
        # copy over steady state matrices
        self.converged = 0

        # Dimensions are the same as usual (have to reset in case previous
        # obs was partially missing case)
        self.k_endog = self.model.k_endog
        self.k_endog2 = self.k_endog**2
        self.k_endogstates = self.k_endog * self.k_states

        # Design matrix is set to zeros
        for i in range(self.model.k_states):
            for j in range(self.model.k_endog):
                self.selected_design[j + i*self.model.k_endog] = 0.0
        self._design = &self.selected_design[0]

        # Change the forecasting step to set the forecast at the intercept
        # $d_t$, so that the forecast error is $v_t = y_t - d_t$.
        self.forecasting = zforecast_missing_conventional

        # Change the updating step to just copy $a_{t|t} = a_t$ and
        # $P_{t|t} = P_t$
        self.updating = zupdating_missing_conventional

        # Change the inversion step to inverse to nans.
        self.inversion = zinverse_missing_conventional

        # Change the loglikelihood calculation to give zero.
        self.calculate_loglikelihood = zloglikelihood_missing_conventional

        # The prediction step is the same as the conventional Kalman
        # filter

    cdef void _select_missing_partial_obs(self):
        cdef:
            int i, j, k, l
            int inc = 1
            int design_t = 0
            int obs_cov_t = 0
        # Mark as not converged so that it does not inappropriately
        # copy over steady state matrices
        self.converged = 0

        # Set dimensions
        self.k_endog = self.model.k_endog - self.model.nmissing[self.t]
        self.k_endog2 = self.k_endog**2
        self.k_endogstates = self.k_endog * self.k_states

        if self.model.design.shape[2] > 1: design_t = self.t
        if self.model.obs_cov.shape[2] > 1: obs_cov_t = self.t

        k = 0
        for i in range(self.model.k_endog):
            if not self.model.missing[i, self.t]:

                self.selected_obs[k] = self.model.obs[i, self.t]

                # i is rows
                # k is rows
                zcopy(&self.model.k_states,
                      &self.model.design[i, 0, design_t], &self.model.k_endog,
                      &self.selected_design[k], &self.k_endog)

                # i, k is columns
                # j, l is rows
                l = 0
                for j in range(self.model.k_endog):
                    if not self.model.missing[j, self.t]:
                        self.selected_obs_cov[l + k*self.k_endog] = self.model.obs_cov[j, i, obs_cov_t]
                        l += 1
                k += 1
        self._obs = &self.selected_obs[0]
        self._design = &self.selected_design[0]
        self._obs_cov = &self.selected_obs_cov[0]

    cdef void post_convergence(self):
        # TODO this should probably be defined separately for each Kalman filter type - e.g. `post_convergence_conventional`, etc.

        # Constants
        cdef:
            int inc = 1

        if self.converged:
            # $F_t$
            zcopy(&self.k_endog2, self._converged_forecast_error_cov, &inc, self._forecast_error_cov, &inc)
            # $P_{t|t}$
            zcopy(&self.k_states2, self._converged_filtered_state_cov, &inc, self._filtered_state_cov, &inc)
            # $P_t$
            zcopy(&self.k_states2, self._converged_predicted_state_cov, &inc, self._predicted_state_cov, &inc)
            # $|F_t|$
            self.determinant = self.converged_determinant

    cdef void numerical_stability(self):
        cdef int i, j
        cdef int predicted_t = self.t
        cdef np.complex128_t value

        if self.conserve_memory & MEMORY_NO_PREDICTED:
            predicted_t = 1

        if self.stability_method & STABILITY_FORCE_SYMMETRY:
            # Enforce symmetry of predicted covariance matrix  
            # $P_{t+1} = 0.5 * (P_{t+1} + P_{t+1}')$  
            # See Grewal (2001), Section 6.3.1.1
            for i in range(self.k_states):
                for j in range(i, self.k_states):
                    value = 0.5 * (
                        self.predicted_state_cov[i,j,predicted_t+1] +
                        self.predicted_state_cov[j,i,predicted_t+1]
                    )
                    self.predicted_state_cov[i,j,predicted_t+1] = value
                    self.predicted_state_cov[j,i,predicted_t+1] = value

    cdef void check_convergence(self):
        # Constants
        cdef:
            int inc = 1
            np.complex128_t alpha = 1.0
            np.complex128_t beta = 0.0
            np.complex128_t gamma = -1.0
        # Indices for arrays that may or may not be stored completely
        cdef:
            int forecast_t = self.t
            int filtered_t = self.t
            int predicted_t = self.t
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            forecast_t = 1
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            filtered_t = 1
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            predicted_t = 1

        if self.time_invariant and not self.converged and self.model.nmissing[self.t] == 0:
            # #### Check for steady-state convergence
            # 
            # `tmp0` array used here, dimension $(m \times m)$  
            # `tmp1` array used here, dimension $(1 \times 1)$  
            zcopy(&self.k_states2, self._input_state_cov, &inc, self._tmp0, &inc)
            zaxpy(&self.k_states2, &gamma, self._predicted_state_cov, &inc, self._tmp0, &inc)

            zgemv("N", &inc, &self.k_states2, &alpha, self._tmp0, &inc, self._tmp0, &inc, &beta, self._tmp1, &inc)
            if zabs(self._tmp1[0]) < self.tolerance:
                self.converged = 1
                self.period_converged = self.t

            # If we just converged, copy the current iteration matrices to the
            # converged storage
            if self.converged == 1:
                # $F_t$
                zcopy(&self.k_endog2, &self.forecast_error_cov[0, 0, forecast_t], &inc, self._converged_forecast_error_cov, &inc)
                # $P_{t|t}$
                zcopy(&self.k_states2, &self.filtered_state_cov[0, 0, filtered_t], &inc, self._converged_filtered_state_cov, &inc)
                # $P_t$
                zcopy(&self.k_states2, &self.predicted_state_cov[0, 0, predicted_t], &inc, self._converged_predicted_state_cov, &inc)
                # $|F_t|$
                self.converged_determinant = self.determinant
        elif self.period_converged > 0:
            # This is here so that the filter's state is reset to converged = 1
            # even if it was set to converged = 0 for the current iteration
            # due to missing values
            self.converged = 1

    cdef void migrate_storage(self):
        cdef int inc = 1

        # Forecast: 1 -> 0
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            zcopy(&self.k_endog, &self.forecast[0, 1], &inc, &self.forecast[0, 0], &inc)
            zcopy(&self.k_endog, &self.forecast_error[0, 1], &inc, &self.forecast_error[0, 0], &inc)
            zcopy(&self.k_endog2, &self.forecast_error_cov[0, 0, 1], &inc, &self.forecast_error_cov[0, 0, 0], &inc)

        # Filtered: 1 -> 0
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            zcopy(&self.k_states, &self.filtered_state[0, 1], &inc, &self.filtered_state[0, 0], &inc)
            zcopy(&self.k_states2, &self.filtered_state_cov[0, 0, 1], &inc, &self.filtered_state_cov[0, 0, 0], &inc)

        # Predicted: 1 -> 0
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            zcopy(&self.k_states, &self.predicted_state[0, 1], &inc, &self.predicted_state[0, 0], &inc)
            zcopy(&self.k_states2, &self.predicted_state_cov[0, 0, 1], &inc, &self.predicted_state_cov[0, 0, 0], &inc)

            # Predicted: 2 -> 1
            zcopy(&self.k_states, &self.predicted_state[0, 2], &inc, &self.predicted_state[0, 1], &inc)
            zcopy(&self.k_states2, &self.predicted_state_cov[0, 0, 2], &inc, &self.predicted_state_cov[0, 0, 1], &inc)

## State Space Representation
cdef class cStatespace(object):
    """
    cStatespace(obs, design, obs_intercept, obs_cov, transition, state_intercept, selection, state_cov)

    *See Durbin and Koopman (2012), Chapter 4 for all notation*
    """

    # ### State space representation
    # 
    # $$
    # \begin{align}
    # y_t & = Z_t \alpha_t + d_t + \varepsilon_t \hspace{3em} & \varepsilon_t & \sim N(0, H_t) \\\\
    # \alpha_{t+1} & = T_t \alpha_t + c_t + R_t \eta_t & \eta_t & \sim N(0, Q_t) \\\\
    # & & \alpha_1 & \sim N(a_1, P_1)
    # \end{align}
    # $$
    # 
    # $y_t$ is $p \times 1$  
    # $\varepsilon_t$ is $p \times 1$  
    # $\alpha_t$ is $m \times 1$  
    # $\eta_t$ is $r \times 1$  
    # $t = 1, \dots, T$

    # `nobs` $\equiv T$ is the length of the time-series  
    # `k_endog` $\equiv p$ is dimension of observation space  
    # `k_states` $\equiv m$ is the dimension of the state space  
    # `k_posdef` $\equiv r$ is the dimension of the state shocks  
    # *Old notation: T, n, k, g*
    cdef readonly int nobs, k_endog, k_states, k_posdef
    
    # `obs` $\equiv y_t$ is the **observation vector** $(p \times T)$  
    # `design` $\equiv Z_t$ is the **design vector** $(p \times m \times T)$  
    # `obs_intercept` $\equiv d_t$ is the **observation intercept** $(p \times T)$  
    # `obs_cov` $\equiv H_t$ is the **observation covariance matrix** $(p \times p \times T)$  
    # `transition` $\equiv T_t$ is the **transition matrix** $(m \times m \times T)$  
    # `state_intercept` $\equiv c_t$ is the **state intercept** $(m \times T)$  
    # `selection` $\equiv R_t$ is the **selection matrix** $(m \times r \times T)$  
    # `state_cov` $\equiv Q_t$ is the **state covariance matrix** $(r \times r \times T)$  
    # `selected_state_cov` $\equiv R Q_t R'$ is the **selected state covariance matrix** $(m \times m \times T)$  
    # `initial_state` $\equiv a_1$ is the **initial state mean** $(m \times 1)$  
    # `initial_state_cov` $\equiv P_1$ is the **initial state covariance matrix** $(m \times m)$
    #
    # With the exception of `obs`, these are *optionally* time-varying. If they are instead time-invariant,
    # then the dimension of length $T$ is instead of length $1$.
    #
    # *Note*: the initial vectors' notation 1-indexed as in Durbin and Koopman,
    # but in the recursions below it will be 0-indexed in the Python arrays.
    # 
    # *Old notation: y, -, mu, beta_tt_init, P_tt_init*
    cdef readonly np.complex64_t [::1,:] obs, obs_intercept, state_intercept
    cdef readonly np.complex64_t [:] initial_state
    cdef readonly np.complex64_t [::1,:] initial_state_cov
    # *Old notation: H, R, F, G, Q*, G Q* G'*
    cdef readonly np.complex64_t [::1,:,:] design, obs_cov, transition, selection, state_cov, selected_state_cov

    # `missing` is a $(p \times T)$ boolean matrix where a row is a $(p \times 1)$ vector
    # in which the $i$th position is $1$ if $y_{i,t}$ is to be considered a missing value.  
    # *Note:* This is created as the output of np.isnan(obs).
    cdef readonly int [::1,:] missing
    # `nmissing` is an `T \times 0` integer vector holding the number of *missing* observations
    # $p - p_t$
    cdef readonly int [:] nmissing

    # Flag for a time-invariant model, which requires that *all* of the
    # possibly time-varying arrays are time-invariant.
    cdef readonly int time_invariant

    # Flag for initialization.
    cdef readonly int initialized

    # Temporary arrays
    cdef np.complex64_t [::1,:] tmp

    # Pointers  
    # *Note*: These are not yet implemented to do anything in this base class
    # but are used in subclasses. Necessary to have them here due to problems
    # with redeclaring the model attribute of KalmanFilter children classes
    cdef np.complex64_t * _obs
    cdef np.complex64_t * _design
    cdef np.complex64_t * _obs_intercept
    cdef np.complex64_t * _obs_cov
    cdef np.complex64_t * _transition
    cdef np.complex64_t * _state_intercept
    cdef np.complex64_t * _selection
    cdef np.complex64_t * _state_cov
    cdef np.complex64_t * _selected_state_cov
    cdef np.complex64_t * _initial_state
    cdef np.complex64_t * _initial_state_cov

    # ### Initialize state space model
    # *Note*: The initial state and state covariance matrix must be provided.
    def __init__(self,
                 np.complex64_t [::1,:]   obs,
                 np.complex64_t [::1,:,:] design,
                 np.complex64_t [::1,:]   obs_intercept,
                 np.complex64_t [::1,:,:] obs_cov,
                 np.complex64_t [::1,:,:] transition,
                 np.complex64_t [::1,:]   state_intercept,
                 np.complex64_t [::1,:,:] selection,
                 np.complex64_t [::1,:,:] state_cov):

        # Local variables
        cdef:
            np.npy_intp dim1[1]
            np.npy_intp dim2[2]
            np.npy_intp dim3[3]

        # #### State space representation variables  
        # **Note**: these arrays share data with the versions defined in
        # Python and passed to this constructor, so if they are updated in
        # Python they will also be updated here.
        self.obs = obs
        self.design = design
        self.obs_intercept = obs_intercept
        self.obs_cov = obs_cov
        self.transition = transition
        self.state_intercept = state_intercept
        self.selection = selection
        self.state_cov = state_cov

        # Dimensions
        self.k_endog = obs.shape[0]
        self.k_states = selection.shape[0]
        self.k_posdef = selection.shape[1]
        self.nobs = obs.shape[1]

        # #### Validate matrix dimensions
        #
        # Make sure that the given state-space matrices have consistent sizes
        validate_matrix_shape('design', &self.design.shape[0],
                              self.k_endog, self.k_states, self.nobs)
        validate_vector_shape('observation intercept', &self.obs_intercept.shape[0],
                              self.k_endog, self.nobs)
        validate_matrix_shape('observation covariance matrix', &self.obs_cov.shape[0],
                              self.k_endog, self.k_endog, self.nobs)
        validate_matrix_shape('transition', &self.transition.shape[0],
                              self.k_states, self.k_states, self.nobs)
        validate_vector_shape('state intercept', &self.state_intercept.shape[0],
                              self.k_states, self.nobs)
        validate_matrix_shape('state covariance matrix', &self.state_cov.shape[0],
                              self.k_posdef, self.k_posdef, self.nobs)

        # Check for a time-invariant model
        self.time_invariant = (
            self.design.shape[2] == 1           and
            self.obs_intercept.shape[1] == 1    and
            self.obs_cov.shape[2] == 1          and
            self.transition.shape[2] == 1       and
            self.state_intercept.shape[1] == 1  and
            self.selection.shape[2] == 1        and
            self.state_cov.shape[2] == 1
        )

        # Set the flag for initialization to be false
        self.initialized = False

        # Allocate selected state covariance matrix
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = 1;
        # (we only allocate memory for time-varying array if necessary)
        if self.state_cov.shape[2] > 1 or self.selection.shape[2] > 1:
            dim3[2] = self.nobs
        self.selected_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_COMPLEX64, FORTRAN)

        # Handle missing data
        self.missing = np.array(np.isnan(obs), dtype=np.int32, order="F")
        self.nmissing = np.array(np.sum(self.missing, axis=0), dtype=np.int32)

        # Create the temporary array
        # Holds arrays of dimension $(m \times m)$
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.tmp = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)

    # ## Initialize: known values
    #
    # Initialize the filter with specific values, assumed to be known with
    # certainty or else as filled with parameters from a maximum likelihood
    # estimation run.
    def initialize_known(self, np.complex64_t [:] initial_state, np.complex64_t [::1,:] initial_state_cov):
        """
        initialize_known(initial_state, initial_state_cov)
        """
        validate_vector_shape('inital state', &initial_state.shape[0], self.k_states, None)
        validate_matrix_shape('initial state covariance', &initial_state_cov.shape[0], self.k_states, self.k_states, None)

        self.initial_state = initial_state
        self.initial_state_cov = initial_state_cov

        self.initialized = True

    # ## Initialize: approximate diffuse priors
    #
    # Durbin and Koopman note that this initialization should only be coupled
    # with the standard Kalman filter for "approximate exploratory work" and
    # can lead to "large rounding errors" (p. 125).
    # 
    # *Note:* see Durbin and Koopman section 5.6.1
    def initialize_approximate_diffuse(self, variance=1e2):
        """
        initialize_approximate_diffuse(variance=1e2)
        """
        cdef np.npy_intp dim[1]
        dim[0] = self.k_states
        self.initial_state = np.PyArray_ZEROS(1, dim, np.NPY_COMPLEX64, FORTRAN)
        self.initial_state_cov = np.eye(self.k_states, dtype=np.complex64).T * variance

        self.initialized = True

    # ## Initialize: stationary process
    # *Note:* see Durbin and Koopman section 5.6.2
    # 
    # TODO improve efficiency with direct BLAS / LAPACK calls
    def initialize_stationary(self):
        """
        initialize_stationary()
        """
        cdef np.npy_intp dim[1]

        # Create selected state covariance matrix
        cselect_state_cov(self.k_states, self.k_posdef,
                                   &self.tmp[0,0],
                                   &self.selection[0,0,0],
                                   &self.state_cov[0,0,0],
                                   &self.selected_state_cov[0,0,0])

        from scipy.linalg import solve_discrete_lyapunov

        dim[0] = self.k_states
        self.initial_state = np.PyArray_ZEROS(1, dim, np.NPY_COMPLEX64, FORTRAN)
        self.initial_state_cov = solve_discrete_lyapunov(
            np.array(self.transition[:,:,0], dtype=np.complex64),
            np.array(self.selected_state_cov[:,:,0], dtype=np.complex64)
        ).T

        self.initialized = True

# ### Selected state covariance matrice
cdef int cselect_state_cov(int k_states, int k_posdef,
                                    np.complex64_t * tmp,
                                    np.complex64_t * selection,
                                    np.complex64_t * state_cov,
                                    np.complex64_t * selected_state_cov):
    cdef:
        np.complex64_t alpha = 1.0
        np.complex64_t beta = 0.0

    # Only need to do something if there is a state covariance matrix
    # (i.e k_posdof == 0)
    if k_posdef > 0:

        # #### Calculate selected state covariance matrix  
        # $Q_t^* = R_t Q_t R_t'$
        # 
        # Combine the selection matrix and the state covariance matrix to get
        # the simplified (but possibly singular) "selected" state covariance
        # matrix (see e.g. Durbin and Koopman p. 43)

        # `tmp0` array used here, dimension $(m \times r)$  

        # $\\#_0 = 1.0 * R_t Q_t$  
        # $(m \times r) = (m \times r) (r \times r)$
        cgemm("N", "N", &k_states, &k_posdef, &k_posdef,
              &alpha, selection, &k_states,
                      state_cov, &k_posdef,
              &beta, tmp, &k_states)
        # $Q_t^* = 1.0 * \\#_0 R_t'$  
        # $(m \times m) = (m \times r) (m \times r)'$
        cgemm("N", "T", &k_states, &k_states, &k_posdef,
              &alpha, tmp, &k_states,
                      selection, &k_states,
              &beta, selected_state_cov, &k_states)

# ## Kalman filter Routines
# 
# The following functions are the workhorse functions for the Kalman filter.
# They represent four distinct but very general phases of the Kalman filtering
# operations.
#
# Their argument is an object of class ?KalmanFilter, which is a stateful
# representation of the recursive filter. For this reason, the below functions
# work almost exclusively through *side-effects* and most return void.
# See the Kalman filter class documentation for further discussion.
#
# They are defined this way so that the actual filtering process can select
# whichever filter type is appropriate for the given time period. For example,
# in the case of state space models with non-stationary components, the filter
# should begin with the exact initial Kalman filter routines but after some
# number of time periods will transition to the conventional Kalman filter
# routines.
#
# Below, `<filter type>` will refer to one of the following:
#
# - `conventional` - the conventional Kalman filter
#
# Other filter types (e.g. `exact_initial`, `augmented`, etc.) may be added in
# the future.
# 
# `forecast_<filter type>` generates the forecast, forecast error $v_t$ and
# forecast error covariance matrix $F_t$  
# `updating_<filter type>` is the updating step of the Kalman filter, and
# generates the filtered state $a_{t|t}$ and covariance matrix $P_{t|t}$  
# `prediction_<filter type>` is the prediction step of the Kalman filter, and
# generates the predicted state $a_{t+1}$ and covariance matrix $P_{t+1}$.
# `loglikelihood_<filter type>` calculates the loglikelihood for $y_t$

# ### Missing Observation Conventional Kalman filter
#
# See Durbin and Koopman (2012) Chapter 4.10
#
# Here k_endog is the same as usual, but the design matrix and observation
# covariance matrix are enforced to be zero matrices, and the loglikelihood
# is defined to be zero.

cdef int cforecast_missing_conventional(cKalmanFilter kfilter):
    cdef int i, j
    cdef int inc = 1

    # #### Forecast for time t  
    # `forecast` $= Z_t a_t + d_t$
    # Just set to zeros, see below (this means if forecasts are required for
    # this part, they must be done in the wrappe)

    # #### Forecast error for time t  
    # It is undefined here, since obs is nan
    for i in range(kfilter.k_endog):
        kfilter._forecast[i] = 0
        kfilter._forecast_error[i] = 0

    # #### Forecast error covariance matrix for time t  
    # $F_t \equiv 0$
    for i in range(kfilter.k_endog):
        for j in range(kfilter.k_endog):
            kfilter._forecast_error_cov[j + i*kfilter.k_endog] = 0

cdef int cupdating_missing_conventional(cKalmanFilter kfilter):
    cdef int inc = 1

    # Simply copy over the input arrays ($a_t, P_t$) to the filtered arrays
    # ($a_{t|t}, P_{t|t}$)
    ccopy(&kfilter.k_states, kfilter._input_state, &inc, kfilter._filtered_state, &inc)
    ccopy(&kfilter.k_states2, kfilter._input_state_cov, &inc, kfilter._filtered_state_cov, &inc)

cdef np.complex64_t cinverse_missing_conventional(cKalmanFilter kfilter, np.complex64_t determinant)  except *:
    # Since the inverse of the forecast error covariance matrix is not
    # stored, we don't need to fill it (e.g. with NPY_NAN values). Instead,
    # just do a noop here and return a zero determinant ($|0|$).
    return 0.0

cdef np.complex64_t cloglikelihood_missing_conventional(cKalmanFilter kfilter, np.complex64_t determinant):
    return 0.0

# ### Conventional Kalman filter
#
# The following are the above routines as defined in the conventional Kalman
# filter.
#
# See Durbin and Koopman (2012) Chapter 4

cdef int cforecast_conventional(cKalmanFilter kfilter):

    # Constants
    cdef:
        int inc = 1, ld
        np.complex64_t alpha = 1.0
        np.complex64_t beta = 0.0
        np.complex64_t gamma = -1.0

    # #### Forecast for time t  
    # `forecast` $= Z_t a_t + d_t$
    # 
    # *Note*: $a_t$ is given from the initialization (for $t = 0$) or
    # from the previous iteration of the filter (for $t > 0$).

    # $\\# = d_t$
    ccopy(&kfilter.k_endog, kfilter._obs_intercept, &inc, kfilter._forecast, &inc)
    # `forecast` $= 1.0 * Z_t a_t + 1.0 * \\#$  
    # $(p \times 1) = (p \times m) (m \times 1) + (p \times 1)$
    cgemv("N", &kfilter.k_endog, &kfilter.k_states,
          &alpha, kfilter._design, &kfilter.k_endog,
                  kfilter._input_state, &inc,
          &alpha, kfilter._forecast, &inc)

    # #### Forecast error for time t  
    # `forecast_error` $\equiv v_t = y_t -$ `forecast`

    # $\\# = y_t$
    ccopy(&kfilter.k_endog, kfilter._obs, &inc, kfilter._forecast_error, &inc)
    # $v_t = -1.0 * $ `forecast` $ + \\#$
    # $(p \times 1) = (p \times 1) + (p \times 1)$
    caxpy(&kfilter.k_endog, &gamma, kfilter._forecast, &inc, kfilter._forecast_error, &inc)

    # *Intermediate calculation* (used just below and then once more)  
    # `tmp1` array used here, dimension $(m \times p)$  
    # $\\#_1 = P_t Z_t'$  
    # $(m \times p) = (m \times m) (p \times m)'$
    cgemm("N", "T", &kfilter.k_states, &kfilter.k_endog, &kfilter.k_states,
          &alpha, kfilter._input_state_cov, &kfilter.k_states,
                  kfilter._design, &kfilter.k_endog,
          &beta, kfilter._tmp1, &kfilter.k_states)

    # #### Forecast error covariance matrix for time t  
    # $F_t \equiv Z_t P_t Z_t' + H_t$
    # 
    # *Note*: this and does nothing at all to `forecast_error_cov` if
    # converged == True
    if not kfilter.converged:
        # $\\# = H_t$
        ccopy(&kfilter.k_endog2, kfilter._obs_cov, &inc, kfilter._forecast_error_cov, &inc)

        # $F_t = 1.0 * Z_t \\#_1 + 1.0 * \\#$
        cgemm("N", "N", &kfilter.k_endog, &kfilter.k_endog, &kfilter.k_states,
              &alpha, kfilter._design, &kfilter.k_endog,
                     kfilter._tmp1, &kfilter.k_states,
              &alpha, kfilter._forecast_error_cov, &kfilter.k_endog)

    return 0

cdef int cupdating_conventional(cKalmanFilter kfilter):
    # Constants
    cdef:
        int inc = 1
        np.complex64_t alpha = 1.0
        np.complex64_t beta = 0.0
        np.complex64_t gamma = -1.0
    
    # #### Filtered state for time t
    # $a_{t|t} = a_t + P_t Z_t' F_t^{-1} v_t$  
    # $a_{t|t} = 1.0 * \\#_1 \\#_2 + 1.0 a_t$
    ccopy(&kfilter.k_states, kfilter._input_state, &inc, kfilter._filtered_state, &inc)
    cgemv("N", &kfilter.k_states, &kfilter.k_endog,
          &alpha, kfilter._tmp1, &kfilter.k_states,
                  kfilter._tmp2, &inc,
          &alpha, kfilter._filtered_state, &inc)

    # #### Filtered state covariance for time t
    # $P_{t|t} = P_t - P_t Z_t' F_t^{-1} Z_t P_t$  
    # $P_{t|t} = P_t - \\#_1 \\#_3 P_t$  
    # 
    # *Note*: this and does nothing at all to `filtered_state_cov` if
    # converged == True
    if not kfilter.converged:
        ccopy(&kfilter.k_states2, kfilter._input_state_cov, &inc, kfilter._filtered_state_cov, &inc)

        # `tmp0` array used here, dimension $(m \times m)$  
        # $\\#_0 = 1.0 * \\#_1 \\#_3$  
        # $(m \times m) = (m \times p) (p \times m)$
        cgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_endog,
              &alpha, kfilter._tmp1, &kfilter.k_states,
                      kfilter._tmp3, &kfilter.k_endog,
              &beta, kfilter._tmp0, &kfilter.k_states)

        # $P_{t|t} = - 1.0 * \\# P_t + 1.0 * P_t$  
        # $(m \times m) = (m \times m) (m \times m) + (m \times m)$
        cgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &gamma, kfilter._tmp0, &kfilter.k_states,
                      kfilter._input_state_cov, &kfilter.k_states,
              &alpha, kfilter._filtered_state_cov, &kfilter.k_states)

    return 0

cdef int cprediction_conventional(cKalmanFilter kfilter):

    # Constants
    cdef:
        int inc = 1
        np.complex64_t alpha = 1.0
        np.complex64_t beta = 0.0
        np.complex64_t gamma = -1.0

    # #### Predicted state for time t+1
    # $a_{t+1} = T_t a_{t|t} + c_t$
    ccopy(&kfilter.k_states, kfilter._state_intercept, &inc, kfilter._predicted_state, &inc)
    cgemv("N", &kfilter.k_states, &kfilter.k_states,
          &alpha, kfilter._transition, &kfilter.k_states,
                  kfilter._filtered_state, &inc,
          &alpha, kfilter._predicted_state, &inc)

    # #### Predicted state covariance matrix for time t+1
    # $P_{t+1} = T_t P_{t|t} T_t' + Q_t^*$
    #
    # *Note*: this and does nothing at all to `predicted_state_cov` if
    # converged == True
    if not kfilter.converged:
        ccopy(&kfilter.k_states2, kfilter._selected_state_cov, &inc, kfilter._predicted_state_cov, &inc)
        # `tmp0` array used here, dimension $(m \times m)$  

        # $\\#_0 = T_t P_{t|t} $

        # $(m \times m) = (m \times m) (m \times m)$
        cgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &alpha, kfilter._transition, &kfilter.k_states,
                      kfilter._filtered_state_cov, &kfilter.k_states,
              &beta, kfilter._tmp0, &kfilter.k_states)
        # $P_{t+1} = 1.0 \\#_0 T_t' + 1.0 \\#$  
        # $(m \times m) = (m \times m) (m \times m) + (m \times m)$
        cgemm("N", "T", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &alpha, kfilter._tmp0, &kfilter.k_states,
                      kfilter._transition, &kfilter.k_states,
              &alpha, kfilter._predicted_state_cov, &kfilter.k_states)

    return 0


cdef np.complex64_t cloglikelihood_conventional(cKalmanFilter kfilter, np.complex64_t determinant):
    # Constants
    cdef:
        np.complex64_t loglikelihood
        int inc = 1
        np.complex64_t alpha = 1.0
        np.complex64_t beta = 0.0

    loglikelihood = -0.5*(kfilter.k_endog*zlog(2*NPY_PI) + zlog(determinant))

    cgemv("N", &inc, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error, &inc,
                           kfilter._tmp2, &inc,
                   &beta, kfilter._tmp0, &inc)
    loglikelihood = loglikelihood - 0.5 * kfilter._tmp0[0]

    return loglikelihood

# ## Forecast error covariance inversion
#
# The following are routines that can calculate the inverse of the forecast
# error covariance matrix (defined in `forecast_<filter type>`).
#
# These routines are aware of the possibility that the Kalman filter may have
# converged to a steady state, in which case they do not need to perform the
# inversion or calculate the determinant.

cdef np.complex64_t cinverse_univariate(cKalmanFilter kfilter, np.complex64_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using simple division
    in the case that the observations are univariate.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    # #### Intermediate values
    cdef:
        int inc = 1
        np.complex64_t scalar

    # Take the inverse of the forecast error covariance matrix
    if not kfilter.converged:
        determinant = kfilter._forecast_error_cov[0]
    try:
        scalar = 1.0 / kfilter._forecast_error_cov[0]
    except:
        raise np.linalg.LinAlgError('Non-positive-definite forecast error'
                                   ' covariance matrix encountered at'
                                   ' period %d' % kfilter.t)
    kfilter._tmp2[0] = scalar * kfilter._forecast_error[0]
    ccopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    cscal(&kfilter.k_endogstates, &scalar, kfilter._tmp3, &inc)

    return determinant

cdef np.complex64_t cfactorize_cholesky(cKalmanFilter kfilter, np.complex64_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using a Cholesky
    decomposition. Called by either of the `solve_cholesky` or
    `invert_cholesky` routines.

    Requires a positive definite matrix, but is faster than an LU
    decomposition.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int inc = 1
        int info
        int i

    if not kfilter.converged:
        ccopy(&kfilter.k_endog2, kfilter._forecast_error_cov, &inc, kfilter._forecast_error_fac, &inc)
        cpotrf("U", &kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog, &info)

        if info < 0:
            raise np.linalg.LinAlgError('Illegal value in forecast error'
                                        ' covariance matrix encountered at'
                                        ' period %d' % kfilter.t)
        if info > 0:
            raise np.linalg.LinAlgError('Non-positive-definite forecast error'
                                       ' covariance matrix encountered at'
                                       ' period %d' % kfilter.t)

        # Calculate the determinant (just the squared product of the
        # diagonals, in the Cholesky decomposition case)
        determinant = 1.0
        for i in range(kfilter.k_endog):
            determinant = determinant * kfilter.forecast_error_fac[i, i]
        determinant = determinant**2

    return determinant

cdef np.complex64_t cfactorize_lu(cKalmanFilter kfilter, np.complex64_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using an LU
    decomposition. Called by either of the `solve_lu` or `invert_lu`
    routines.

    Is slower than a Cholesky decomposition, but does not require a
    positive definite matrix.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int inc = 1
        int info
        int i

    if not kfilter.converged:
        # Perform LU decomposition into `forecast_error_fac`
        ccopy(&kfilter.k_endog2, kfilter._forecast_error_cov, &inc, kfilter._forecast_error_fac, &inc)
        
        cgetrf(&kfilter.k_endog, &kfilter.k_endog,
                        kfilter._forecast_error_fac, &kfilter.k_endog,
                        kfilter._forecast_error_ipiv, &info)

        if info < 0:
            raise np.linalg.LinAlgError('Illegal value in forecast error'
                                        ' covariance matrix encountered at'
                                        ' period %d' % kfilter.t)
        if info > 0:
            raise np.linalg.LinAlgError('Singular forecast error covariance'
                                        ' matrix encountered at period %d' %
                                        kfilter.t)

        # Calculate the determinant (product of the diagonals, but with
        # sign modifications according to the permutation matrix)    
        determinant = 1
        for i in range(kfilter.k_endog):
            if not kfilter._forecast_error_ipiv[i] == i+1:
                determinant *= -1*kfilter.forecast_error_fac[i, i]
            else:
                determinant *= kfilter.forecast_error_fac[i, i]

    return determinant

cdef np.complex64_t cinverse_cholesky(cKalmanFilter kfilter, np.complex64_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        int i, j
        np.complex64_t alpha = 1.0
        np.complex64_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = cfactorize_cholesky(kfilter, determinant)

        # Continue taking the inverse
        cpotri("U", &kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog, &info)

        # ?potri only fills in the upper triangle of the symmetric array, and
        # since the ?symm and ?symv routines are not available as of scipy
        # 0.11.0, we can't use them, so we must fill in the lower triangle
        # by hand
        for i in range(kfilter.k_endog):
            for j in range(i):
                kfilter.forecast_error_fac[i,j] = kfilter.forecast_error_fac[j,i]


    # Get `tmp2` and `tmp3` via matrix multiplications

    # `tmp2` array used here, dimension $(p \times 1)$  
    # $\\#_2 = F_t^{-1} v_t$  
    #csymv("U", &kfilter.k_endog, &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
    #               kfilter._forecast_error, &inc, &beta, kfilter._tmp2, &inc)
    cgemv("N", &kfilter.k_endog, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._forecast_error, &inc,
                   &beta, kfilter._tmp2, &inc)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $\\#_3 = F_t^{-1} Z_t$
    #csymm("L", "U", &kfilter.k_endog, &kfilter.k_states,
    #               &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
    #                       kfilter._design, &kfilter.k_endog,
    #               &beta, kfilter._tmp3, &kfilter.k_endog)
    cgemm("N", "N", &kfilter.k_endog, &kfilter.k_states, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._design, &kfilter.k_endog,
                   &beta, kfilter._tmp3, &kfilter.k_endog)

    return determinant

cdef np.complex64_t cinverse_lu(cKalmanFilter kfilter, np.complex64_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        np.complex64_t alpha = 1.0
        np.complex64_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = cfactorize_lu(kfilter, determinant)

        # Continue taking the inverse
        cgetri(&kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog,
               kfilter._forecast_error_ipiv, kfilter._forecast_error_work, &kfilter.ldwork, &info)

    # Get `tmp2` and `tmp3` via matrix multiplications

    # `tmp2` array used here, dimension $(p \times 1)$  
    # $\\#_2 = F_t^{-1} v_t$  
    cgemv("N", &kfilter.k_endog, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._forecast_error, &inc,
                   &beta, kfilter._tmp2, &inc)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $\\#_3 = F_t^{-1} Z_t$
    cgemm("N", "N", &kfilter.k_endog, &kfilter.k_states, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._design, &kfilter.k_endog,
                   &beta, kfilter._tmp3, &kfilter.k_endog)

    return determinant

cdef np.complex64_t csolve_cholesky(cKalmanFilter kfilter, np.complex64_t determinant) except *:
    """
    solve_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = cfactorize_cholesky(kfilter, determinant)

    # Solve the linear systems  
    # `tmp2` array used here, dimension $(p \times 1)$  
    # $F_t \\#_2 = v_t$  
    ccopy(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)
    cpotrs("U", &kfilter.k_endog, &inc, kfilter._forecast_error_fac, &kfilter.k_endog, kfilter._tmp2, &kfilter.k_endog, &info)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $F_t \\#_3 = Z_t$
    ccopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    cpotrs("U", &kfilter.k_endog, &kfilter.k_states, kfilter._forecast_error_fac, &kfilter.k_endog, kfilter._tmp3, &kfilter.k_endog, &info)

    return determinant

cdef np.complex64_t csolve_lu(cKalmanFilter kfilter, np.complex64_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        np.complex64_t alpha = 1.0
        np.complex64_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = cfactorize_lu(kfilter, determinant)

    # Solve the linear systems  
    # `tmp2` array used here, dimension $(p \times 1)$  
    # $F_t \\#_2 = v_t$  
    ccopy(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)
    cgetrs("N", &kfilter.k_endog, &inc, kfilter._forecast_error_fac, &kfilter.k_endog,
                    kfilter._forecast_error_ipiv, kfilter._tmp2, &kfilter.k_endog, &info)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $F_t \\#_3 = Z_t$
    ccopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    cgetrs("N", &kfilter.k_endog, &kfilter.k_states, kfilter._forecast_error_fac, &kfilter.k_endog,
                    kfilter._forecast_error_ipiv, kfilter._tmp3, &kfilter.k_endog, &info)

    return determinant


# ## Kalman filter

cdef class cKalmanFilter(object):
    """
    cKalmanFilter(model, filter=FILTER_CONVENTIONAL, inversion_method=INVERT_UNIVARIATE | SOLVE_CHOLESKY, stability_method=STABILITY_FORCE_SYMMETRY, tolerance=1e-19)

    A representation of the Kalman filter recursions.

    While the filter is mathematically represented as a recursion, it is here
    translated into Python as a stateful iterator.

    Because there are actually several types of Kalman filter depending on the
    state space model of interest, this class only handles the *iteration*
    aspect of filtering, and delegates the actual operations to four general
    workhorse routines, which can be implemented separately for each type of
    Kalman filter.

    In order to maintain a consistent interface, and because these four general
    routines may be quite different across filter types, their argument is only
    the stateful ?KalmanFilter object. Furthermore, in order to allow the
    different types of filter to substitute alternate matrices, this class
    defines a set of pointers to the various state space arrays and the
    filtering output arrays.

    For example, handling missing observations requires not only substituting
    `obs`, `design`, and `obs_cov` matrices, but the new matrices actually have
    different dimensions than the originals. This can be flexibly accomodated
    simply by replacing e.g. the `obs` pointer to the substituted `obs` array
    and replacing `k_endog` for that iteration. Then in the next iteration, when
    the `obs` vector may be missing different elements (or none at all), it can
    again be redefined.

    Each iteration of the filter (see `__next__`) proceeds in a number of
    steps.

    `initialize_object_pointers` initializes pointers to current-iteration
    objects (i.e. the state space arrays and filter output arrays).  

    `initialize_function_pointers` initializes pointers to the appropriate
    Kalman filtering routines (i.e. `forecast_conventional` or
    `forecast_exact_initial`, etc.).  

    `select_arrays` converts the base arrays into "selected" arrays using
    selection matrices. In particular, it handles the state covariance matrix
    and redefined matrices based on missing values.  

    `post_convergence` handles copying arrays from time $t-1$ to time $t$ when
    the Kalman filter has converged and they don't need to be re-calculated.  

    `forecasting` calls the Kalman filter `forcasting_<filter type>` routine

    `inversion` calls the appropriate function to invert the forecast error
    covariance matrix.  

    `updating` calls the Kalman filter `updating_<filter type>` routine

    `loglikelihood` calls the Kalman filter `loglikelihood_<filter type>` routine

    `prediction` calls the Kalman filter `prediction_<filter type>` routine

    `numerical_stability` performs end-of-iteration tasks to improve the numerical
    stability of the filter 

    `check_convergence` checks for convergence of the filter to steady-state.
    """

    # ### Statespace model
    cdef readonly cStatespace model

    # ### Filter parameters
    # Holds the time-iteration state of the filter  
    # *Note*: must be changed using the `seek` method
    cdef readonly int t
    # Holds the tolerance parameter for convergence
    cdef public np.float64_t tolerance
    # Holds the convergence to steady-state status of the filter
    # *Note*: is by default reset each time `seek` is called
    cdef readonly int converged
    cdef readonly int period_converged
    # Holds whether or not the model is time-invariant
    # *Note*: is by default reset each time `seek` is called
    cdef readonly int time_invariant
    # The Kalman filter procedure to use  
    cdef public int filter_method
    # The method by which the terms using the inverse of the forecast
    # error covariance matrix are solved.
    cdef public int inversion_method
    # Methods to improve numerical stability
    cdef public int stability_method
    # Whether or not to conserve memory
    # If True, only stores filtered states and covariance matrices
    cdef readonly int conserve_memory
    # If conserving loglikelihood, the number of periods to "burn"
    # before starting to record the loglikelihood
    cdef readonly int loglikelihood_burn

    # ### Kalman filter properties

    # `loglikelihood` $\equiv \log p(y_t | Y_{t-1})$
    cdef readonly np.complex64_t [:] loglikelihood

    # `filtered_state` $\equiv a_{t|t} = E(\alpha_t | Y_t)$ is the **filtered estimator** of the state $(m \times T)$  
    # `predicted_state` $\equiv a_{t+1} = E(\alpha_{t+1} | Y_t)$ is the **one-step ahead predictor** of the state $(m \times T-1)$  
    # `forecast` $\equiv E(y_t|Y_{t-1})$ is the **forecast** of the next observation $(p \times T)$   
    # `forecast_error` $\equiv v_t = y_t - E(y_t|Y_{t-1})$ is the **one-step ahead forecast error** of the next observation $(p \times T)$  
    # 
    # *Note*: Actual values in `filtered_state` will be from 1 to `nobs`+1. Actual
    # values in `predicted_state` will be from 0 to `nobs`+1 because the initialization
    # is copied over to the zeroth entry, and similar for the covariances, below.
    #
    # *Old notation: beta_tt, beta_tt1, y_tt1, eta_tt1*
    cdef readonly np.complex64_t [::1,:] filtered_state, predicted_state, forecast, forecast_error

    # `filtered_state_cov` $\equiv P_{t|t} = Var(\alpha_t | Y_t)$ is the **filtered state covariance matrix** $(m \times m \times T)$  
    # `predicted_state_cov` $\equiv P_{t+1} = Var(\alpha_{t+1} | Y_t)$ is the **predicted state covariance matrix** $(m \times m \times T)$  
    # `forecast_error_cov` $\equiv F_t = Var(v_t | Y_{t-1})$ is the **forecast error covariance matrix** $(p \times p \times T)$  
    # 
    # *Old notation: P_tt, P_tt1, f_tt1*
    cdef readonly np.complex64_t [::1,:,:] filtered_state_cov, predicted_state_cov, forecast_error_cov

    # ### Steady State Values
    # These matrices are used to hold the converged matrices after the Kalman
    # filter has reached steady-state
    cdef readonly np.complex64_t [::1,:] converged_forecast_error_cov
    cdef readonly np.complex64_t [::1,:] converged_filtered_state_cov
    cdef readonly np.complex64_t [::1,:] converged_predicted_state_cov
    cdef readonly np.complex64_t converged_determinant

    # ### Temporary arrays
    # These matrices are used to temporarily hold selected observation vectors,
    # design matrices, and observation covariance matrices in the case of
    # missing data.  
    cdef readonly np.complex64_t [:] selected_obs
    # The following are contiguous memory segments which are then used to
    # store the data in the above matrices.
    cdef readonly np.complex64_t [:] selected_design
    cdef readonly np.complex64_t [:] selected_obs_cov
    # `forecast_error_fac` is a forecast error covariance matrix **factorization** $(p \times p)$.
    # Depending on the method for handling the inverse of the forecast error covariance matrix, it may be:
    # - a Cholesky factorization if `cholesky_solve` is used
    # - an inverse calculated via Cholesky factorization if `cholesky_inverse` is used
    # - an LU factorization if `lu_solve` is used
    # - an inverse calculated via LU factorization if `lu_inverse` is used
    cdef readonly np.complex64_t [::1,:] forecast_error_fac
    # `forecast_error_ipiv` holds pivot indices if an LU decomposition is used
    cdef readonly int [:] forecast_error_ipiv
    # `forecast_error_work` is a work array for matrix inversion if an LU
    # decomposition is used
    cdef readonly np.complex64_t [::1,:] forecast_error_work
    # These hold the memory allocations of the unnamed temporary arrays
    cdef readonly np.complex64_t [::1,:] tmp0, tmp1, tmp3
    cdef readonly np.complex64_t [:] tmp2

    # Holds the determinant across calculations (this is done because after
    # convergence, it doesn't need to be re-calculated anymore)
    cdef readonly np.complex64_t determinant

    # ### Pointers to current-iteration arrays
    cdef np.complex64_t * _obs
    cdef np.complex64_t * _design
    cdef np.complex64_t * _obs_intercept
    cdef np.complex64_t * _obs_cov
    cdef np.complex64_t * _transition
    cdef np.complex64_t * _state_intercept
    cdef np.complex64_t * _selection
    cdef np.complex64_t * _state_cov
    cdef np.complex64_t * _selected_state_cov
    cdef np.complex64_t * _initial_state
    cdef np.complex64_t * _initial_state_cov

    cdef np.complex64_t * _input_state
    cdef np.complex64_t * _input_state_cov

    cdef np.complex64_t * _forecast
    cdef np.complex64_t * _forecast_error
    cdef np.complex64_t * _forecast_error_cov
    cdef np.complex64_t * _filtered_state
    cdef np.complex64_t * _filtered_state_cov
    cdef np.complex64_t * _predicted_state
    cdef np.complex64_t * _predicted_state_cov

    cdef np.complex64_t * _converged_forecast_error_cov
    cdef np.complex64_t * _converged_filtered_state_cov
    cdef np.complex64_t * _converged_predicted_state_cov

    cdef np.complex64_t * _forecast_error_fac
    cdef int * _forecast_error_ipiv
    cdef np.complex64_t * _forecast_error_work

    cdef np.complex64_t * _tmp0
    cdef np.complex64_t * _tmp1
    cdef np.complex64_t * _tmp2
    cdef np.complex64_t * _tmp3

    # ### Pointers to current-iteration Kalman filtering functions
    cdef int (*forecasting)(
        cKalmanFilter
    )
    cdef np.complex64_t (*inversion)(
        cKalmanFilter, np.complex64_t
    ) except *
    cdef int (*updating)(
        cKalmanFilter
    )
    cdef np.complex64_t (*calculate_loglikelihood)(
        cKalmanFilter, np.complex64_t
    )
    cdef int (*prediction)(
        cKalmanFilter
    )

    # ### Define some constants
    cdef readonly int k_endog, k_states, k_posdef, k_endog2, k_states2, k_endogstates, ldwork
    
    def __init__(self,
                 cStatespace model,
                 int filter_method=FILTER_CONVENTIONAL,
                 int inversion_method=INVERT_UNIVARIATE | SOLVE_CHOLESKY,
                 int stability_method=STABILITY_FORCE_SYMMETRY,
                 int conserve_memory=MEMORY_STORE_ALL,
                 np.float64_t tolerance=1e-19,
                 int loglikelihood_burn=0):
        # Local variables
        cdef:
            np.npy_intp dim1[1]
            np.npy_intp dim2[2]
            np.npy_intp dim3[3]
        cdef int storage

        # Save the model
        self.model = model

        # Initialize filter parameters
        self.tolerance = tolerance
        if not filter_method == FILTER_CONVENTIONAL:
            raise NotImplementedError("Only the conventional Kalman filter is currently implemented")
        self.filter_method = filter_method
        self.inversion_method = inversion_method
        self.stability_method = stability_method
        self.conserve_memory = conserve_memory
        self.loglikelihood_burn = loglikelihood_burn

        # Initialize the constant values
        self.time_invariant = self.model.time_invariant
        self.k_endog = self.model.k_endog
        self.k_states = self.model.k_states
        self.k_posdef = self.model.k_posdef
        self.k_endog2 = self.model.k_endog**2
        self.k_states2 = self.model.k_states**2
        self.k_endogstates = self.model.k_endog * self.model.k_states
        # TODO replace with optimal work array size
        self.ldwork = self.model.k_endog

        # #### Allocate arrays for calculations

        # Arrays for Kalman filter output

        # Forecast
        if self.conserve_memory & MEMORY_NO_FORECAST:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_endog; dim2[1] = storage;
        self.forecast = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        self.forecast_error = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        dim3[0] = self.k_endog; dim3[1] = self.k_endog; dim3[2] = storage;
        self.forecast_error_cov = np.PyArray_ZEROS(3, dim3, np.NPY_COMPLEX64, FORTRAN)

        # Filtered
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_states; dim2[1] = storage;
        self.filtered_state = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = storage;
        self.filtered_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_COMPLEX64, FORTRAN)

        # Predicted
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_states; dim2[1] = storage+1;
        self.predicted_state = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = storage+1;
        self.predicted_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_COMPLEX64, FORTRAN)

        # Likelihood
        if self.conserve_memory & MEMORY_NO_LIKELIHOOD > 0:
            storage = 1
        else:
            storage = self.model.nobs
        dim1[0] = storage
        self.loglikelihood = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX64, FORTRAN)

        # Converged matrices
        dim2[0] = self.k_endog; dim2[1] = self.k_endog;
        self.converged_forecast_error_cov = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        self._converged_forecast_error_cov = &self.converged_forecast_error_cov[0,0]
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.converged_filtered_state_cov = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        self._converged_filtered_state_cov = &self.converged_filtered_state_cov[0,0]
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.converged_predicted_state_cov = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        self._converged_predicted_state_cov = &self.converged_predicted_state_cov[0,0]

        # #### Arrays for temporary calculations
        # *Note*: in math notation below, a $\\#$ will represent a generic
        # temporary array, and a $\\#_i$ will represent a named temporary array.

        # Arrays related to matrix factorizations / inverses
        dim2[0] = self.k_endog; dim2[1] = self.k_endog;
        self.forecast_error_fac = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        self._forecast_error_fac = &self.forecast_error_fac[0,0]
        dim2[0] = self.ldwork; dim2[1] = self.ldwork;
        self.forecast_error_work = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        self._forecast_error_work = &self.forecast_error_work[0,0]
        dim1[0] = self.k_endog;
        self.forecast_error_ipiv = np.PyArray_ZEROS(1, dim1, np.NPY_INT, FORTRAN)
        self._forecast_error_ipiv = &self.forecast_error_ipiv[0]

        # Holds arrays of dimension $(m \times m)$ and $(m \times r)$
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.tmp0 = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        self._tmp0 = &self.tmp0[0, 0]

        # Holds arrays of dimension $(m \times p)$
        dim2[0] = self.k_states; dim2[1] = self.k_endog;
        self.tmp1 = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        self._tmp1 = &self.tmp1[0, 0]

        # Holds arrays of dimension $(p \times 1)$
        dim1[0] = self.k_endog;
        self.tmp2 = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX64, FORTRAN)
        self._tmp2 = &self.tmp2[0]

        # Holds arrays of dimension $(p \times m)$
        dim2[0] = self.k_endog; dim2[1] = self.k_states;
        self.tmp3 = np.PyArray_ZEROS(2, dim2, np.NPY_COMPLEX64, FORTRAN)
        self._tmp3 = &self.tmp3[0, 0]

        # Arrays for missing data
        dim1[0] = self.k_endog;
        self.selected_obs = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX64, FORTRAN)
        dim1[0] = self.k_endog * self.k_states;
        self.selected_design = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX64, FORTRAN)
        dim1[0] = self.k_endog2;
        self.selected_obs_cov = np.PyArray_ZEROS(1, dim1, np.NPY_COMPLEX64, FORTRAN)

        # Initialize time and convergence status
        self.t = 0
        self.converged = 0
        self.period_converged = 0

    cpdef set_filter_method(self, int filter_method, int force_reset=True):
        """
        set_filter_method(self, filter_method, force_reset=True)

        Change the filter method.
        """
        self.filter_method = filter_method

    cpdef seek(self, unsigned int t, int reset_convergence = True):
        """
        seek(self, t, reset_convergence = True)

        Change the time-state of the filter

        Is usually called to reset the filter to the beginning.
        """
        if t >= self.model.nobs:
            raise IndexError("Observation index out of range")
        self.t = t

        if reset_convergence:
            self.converged = 0
            self.period_converged = 0

    def __iter__(self):
        return self

    def __call__(self):
        """
        Iterate the filter across the entire set of observations.
        """
        cdef int i

        self.seek(0, True)
        for i in range(self.model.nobs):
            next(self)

    def __next__(self):
        """
        Perform an iteration of the Kalman filter
        """

        # Get time subscript, and stop the iterator if at the end
        if not self.t < self.model.nobs:
            raise StopIteration

        # Initialize pointers to current-iteration objects
        self.initialize_statespace_object_pointers()
        self.initialize_filter_object_pointers()

        # Initialize pointers to appropriate Kalman filtering functions
        self.initialize_function_pointers()

        # Convert base arrays into "selected" arrays  
        # - State covariance matrix? $Q_t \to R_t Q_t R_t`$
        # - Missing values: $y_t \to W_t y_t$, $Z_t \to W_t Z_t$, $H_t \to W_t H_t$
        self.select_state_cov()
        self.select_missing()

        # Post-convergence: copy previous iteration arrays
        self.post_convergence()

        # Form forecasts
        self.forecasting(self)

        # Perform `forecast_error_cov` inversion (or decomposition)
        self.determinant = self.inversion(self, self.determinant)

        # Updating step
        self.updating(self)

        # Retrieve the loglikelihood
        if self.conserve_memory & MEMORY_NO_LIKELIHOOD > 0:
            if self.t == 0:
                self.loglikelihood[0] = 0
            if self.t >= self.loglikelihood_burn:
                self.loglikelihood[0] = self.loglikelihood[0] + self.calculate_loglikelihood(
                    self, self.determinant
                )
        else:
            self.loglikelihood[self.t] = self.calculate_loglikelihood(
                self, self.determinant
            )

        # Prediction step
        self.prediction(self)

        # Aids to numerical stability
        self.numerical_stability()

        # Check for convergence
        self.check_convergence()

        # If conserving memory, migrate storage: t->t-1, t+1->t
        self.migrate_storage()

        # Advance the time
        self.t += 1

    cdef void initialize_statespace_object_pointers(self) except *:
        cdef:
            int t = self.t
        # Indices for possibly time-varying arrays
        cdef:
            int design_t = 0
            int obs_intercept_t = 0
            int obs_cov_t = 0
            int transition_t = 0
            int state_intercept_t = 0
            int selection_t = 0
            int state_cov_t = 0

        # Get indices for possibly time-varying arrays
        if not self.model.time_invariant:
            if self.model.design.shape[2] > 1:             design_t = t
            if self.model.obs_intercept.shape[1] > 1:      obs_intercept_t = t
            if self.model.obs_cov.shape[2] > 1:            obs_cov_t = t
            if self.model.transition.shape[2] > 1:         transition_t = t
            if self.model.state_intercept.shape[1] > 1:    state_intercept_t = t
            if self.model.selection.shape[2] > 1:          selection_t = t
            if self.model.state_cov.shape[2] > 1:          state_cov_t = t

        # Initialize object-level pointers to statespace arrays
        self._obs = &self.model.obs[0, t]
        self._design = &self.model.design[0, 0, design_t]
        self._obs_intercept = &self.model.obs_intercept[0, obs_intercept_t]
        self._obs_cov = &self.model.obs_cov[0, 0, obs_cov_t]
        self._transition = &self.model.transition[0, 0, transition_t]
        self._state_intercept = &self.model.state_intercept[0, state_intercept_t]
        self._selection = &self.model.selection[0, 0, selection_t]
        self._state_cov = &self.model.state_cov[0, 0, state_cov_t]

        # Initialize object-level pointers to initialization
        if not self.model.initialized:
            raise RuntimeError("Statespace model not initialized.")
        self._initial_state = &self.model.initial_state[0]
        self._initial_state_cov = &self.model.initial_state_cov[0,0]

    cdef void initialize_filter_object_pointers(self):
        cdef:
            int t = self.t
            int inc = 1
        # Indices for arrays that may or may not be stored completely
        cdef:
            int forecast_t = t
            int filtered_t = t
            int predicted_t = t
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            forecast_t = 1
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            filtered_t = 1
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            predicted_t = 1

        # Initialize object-level pointers to input arrays
        self._input_state = &self.predicted_state[0, predicted_t]
        self._input_state_cov = &self.predicted_state_cov[0, 0, predicted_t]

        # Copy initialization arrays to input arrays if we're starting the
        # filter
        if t == 0:
            # `predicted_state[:,0]` $= a_1 =$ `initial_state`  
            # `predicted_state_cov[:,:,0]` $= P_1 =$ `initial_state_cov`  
            ccopy(&self.k_states, self._initial_state, &inc, self._input_state, &inc)
            ccopy(&self.k_states2, self._initial_state_cov, &inc, self._input_state_cov, &inc)

        # Initialize object-level pointers to output arrays
        self._forecast = &self.forecast[0, forecast_t]
        self._forecast_error = &self.forecast_error[0, forecast_t]
        self._forecast_error_cov = &self.forecast_error_cov[0, 0, forecast_t]

        self._filtered_state = &self.filtered_state[0, filtered_t]
        self._filtered_state_cov = &self.filtered_state_cov[0, 0, filtered_t]

        self._predicted_state = &self.predicted_state[0, predicted_t+1]
        self._predicted_state_cov = &self.predicted_state_cov[0, 0, predicted_t+1]

    cdef void initialize_function_pointers(self) except *:
        if self.filter_method & FILTER_CONVENTIONAL:
            self.forecasting = cforecast_conventional

            if self.inversion_method & INVERT_UNIVARIATE and self.k_endog == 1:
                self.inversion = cinverse_univariate
            elif self.inversion_method & SOLVE_CHOLESKY:
                self.inversion = csolve_cholesky
            elif self.inversion_method & SOLVE_LU:
                self.inversion = csolve_lu
            elif self.inversion_method & INVERT_CHOLESKY:
                self.inversion = cinverse_cholesky
            elif self.inversion_method & INVERT_LU:
                self.inversion = cinverse_lu
            else:
                raise NotImplementedError("Invalid inversion method")

            self.updating = cupdating_conventional
            self.calculate_loglikelihood = cloglikelihood_conventional
            self.prediction = cprediction_conventional

        else:
            raise NotImplementedError("Invalid filtering method")

    cdef void select_state_cov(self):
        cdef int selected_state_cov_t = 0

        # ### Get selected state covariance matrix
        if self.t == 0 or self.model.selected_state_cov.shape[2] > 1:
            selected_state_cov_t = self.t
            self._selected_state_cov = &self.model.selected_state_cov[0, 0, selected_state_cov_t]

            cselect_state_cov(self.k_states, self.k_posdef,
                                       self._tmp0,
                                       self._selection,
                                       self._state_cov,
                                       self._selected_state_cov)
        else:
            self._selected_state_cov = &self.model.selected_state_cov[0, 0, 0]

    cdef void select_missing(self):
        # ### Perform missing selections
        # In Durbin and Koopman (2012), these are represented as matrix
        # multiplications, i.e. $Z_t^* = W_t Z_t$ where $W_t$ is a row
        # selection matrix (it contains a subset of rows of the identity
        # matrix).
        #
        # It's more efficient, though, to just copy over the data directly,
        # which is what is done here. Note that the `selected_*` arrays are
        # defined as single-dimensional, so the assignment indexes below are
        # set such that the arrays can be interpreted by the BLAS and LAPACK
        # functions as two-dimensional, column-major arrays.
        #
        # In the case that all data is missing (e.g. this is what happens in
        # forecasting), we actually set don't change the dimension, but we set
        # the design matrix to the zeros array.
        if self.model.nmissing[self.t] == self.model.k_endog:
            self._select_missing_entire_obs()
        elif self.model.nmissing[self.t] > 0:
            self._select_missing_partial_obs()
        else:
            # Reset dimensions
            self.k_endog = self.model.k_endog
            self.k_endog2 = self.k_endog**2
            self.k_endogstates = self.k_endog * self.k_states

    cdef void _select_missing_entire_obs(self):
        cdef:
            int i, j
        # Mark as not converged so that it does not inappropriately
        # copy over steady state matrices
        self.converged = 0

        # Dimensions are the same as usual (have to reset in case previous
        # obs was partially missing case)
        self.k_endog = self.model.k_endog
        self.k_endog2 = self.k_endog**2
        self.k_endogstates = self.k_endog * self.k_states

        # Design matrix is set to zeros
        for i in range(self.model.k_states):
            for j in range(self.model.k_endog):
                self.selected_design[j + i*self.model.k_endog] = 0.0
        self._design = &self.selected_design[0]

        # Change the forecasting step to set the forecast at the intercept
        # $d_t$, so that the forecast error is $v_t = y_t - d_t$.
        self.forecasting = cforecast_missing_conventional

        # Change the updating step to just copy $a_{t|t} = a_t$ and
        # $P_{t|t} = P_t$
        self.updating = cupdating_missing_conventional

        # Change the inversion step to inverse to nans.
        self.inversion = cinverse_missing_conventional

        # Change the loglikelihood calculation to give zero.
        self.calculate_loglikelihood = cloglikelihood_missing_conventional

        # The prediction step is the same as the conventional Kalman
        # filter

    cdef void _select_missing_partial_obs(self):
        cdef:
            int i, j, k, l
            int inc = 1
            int design_t = 0
            int obs_cov_t = 0
        # Mark as not converged so that it does not inappropriately
        # copy over steady state matrices
        self.converged = 0

        # Set dimensions
        self.k_endog = self.model.k_endog - self.model.nmissing[self.t]
        self.k_endog2 = self.k_endog**2
        self.k_endogstates = self.k_endog * self.k_states

        if self.model.design.shape[2] > 1: design_t = self.t
        if self.model.obs_cov.shape[2] > 1: obs_cov_t = self.t

        k = 0
        for i in range(self.model.k_endog):
            if not self.model.missing[i, self.t]:

                self.selected_obs[k] = self.model.obs[i, self.t]

                # i is rows
                # k is rows
                ccopy(&self.model.k_states,
                      &self.model.design[i, 0, design_t], &self.model.k_endog,
                      &self.selected_design[k], &self.k_endog)

                # i, k is columns
                # j, l is rows
                l = 0
                for j in range(self.model.k_endog):
                    if not self.model.missing[j, self.t]:
                        self.selected_obs_cov[l + k*self.k_endog] = self.model.obs_cov[j, i, obs_cov_t]
                        l += 1
                k += 1
        self._obs = &self.selected_obs[0]
        self._design = &self.selected_design[0]
        self._obs_cov = &self.selected_obs_cov[0]

    cdef void post_convergence(self):
        # TODO this should probably be defined separately for each Kalman filter type - e.g. `post_convergence_conventional`, etc.

        # Constants
        cdef:
            int inc = 1

        if self.converged:
            # $F_t$
            ccopy(&self.k_endog2, self._converged_forecast_error_cov, &inc, self._forecast_error_cov, &inc)
            # $P_{t|t}$
            ccopy(&self.k_states2, self._converged_filtered_state_cov, &inc, self._filtered_state_cov, &inc)
            # $P_t$
            ccopy(&self.k_states2, self._converged_predicted_state_cov, &inc, self._predicted_state_cov, &inc)
            # $|F_t|$
            self.determinant = self.converged_determinant

    cdef void numerical_stability(self):
        cdef int i, j
        cdef int predicted_t = self.t
        cdef np.complex64_t value

        if self.conserve_memory & MEMORY_NO_PREDICTED:
            predicted_t = 1

        if self.stability_method & STABILITY_FORCE_SYMMETRY:
            # Enforce symmetry of predicted covariance matrix  
            # $P_{t+1} = 0.5 * (P_{t+1} + P_{t+1}')$  
            # See Grewal (2001), Section 6.3.1.1
            for i in range(self.k_states):
                for j in range(i, self.k_states):
                    value = 0.5 * (
                        self.predicted_state_cov[i,j,predicted_t+1] +
                        self.predicted_state_cov[j,i,predicted_t+1]
                    )
                    self.predicted_state_cov[i,j,predicted_t+1] = value
                    self.predicted_state_cov[j,i,predicted_t+1] = value

    cdef void check_convergence(self):
        # Constants
        cdef:
            int inc = 1
            np.complex64_t alpha = 1.0
            np.complex64_t beta = 0.0
            np.complex64_t gamma = -1.0
        # Indices for arrays that may or may not be stored completely
        cdef:
            int forecast_t = self.t
            int filtered_t = self.t
            int predicted_t = self.t
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            forecast_t = 1
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            filtered_t = 1
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            predicted_t = 1

        if self.time_invariant and not self.converged and self.model.nmissing[self.t] == 0:
            # #### Check for steady-state convergence
            # 
            # `tmp0` array used here, dimension $(m \times m)$  
            # `tmp1` array used here, dimension $(1 \times 1)$  
            ccopy(&self.k_states2, self._input_state_cov, &inc, self._tmp0, &inc)
            caxpy(&self.k_states2, &gamma, self._predicted_state_cov, &inc, self._tmp0, &inc)

            cgemv("N", &inc, &self.k_states2, &alpha, self._tmp0, &inc, self._tmp0, &inc, &beta, self._tmp1, &inc)
            if zabs(self._tmp1[0]) < self.tolerance:
                self.converged = 1
                self.period_converged = self.t

            # If we just converged, copy the current iteration matrices to the
            # converged storage
            if self.converged == 1:
                # $F_t$
                ccopy(&self.k_endog2, &self.forecast_error_cov[0, 0, forecast_t], &inc, self._converged_forecast_error_cov, &inc)
                # $P_{t|t}$
                ccopy(&self.k_states2, &self.filtered_state_cov[0, 0, filtered_t], &inc, self._converged_filtered_state_cov, &inc)
                # $P_t$
                ccopy(&self.k_states2, &self.predicted_state_cov[0, 0, predicted_t], &inc, self._converged_predicted_state_cov, &inc)
                # $|F_t|$
                self.converged_determinant = self.determinant
        elif self.period_converged > 0:
            # This is here so that the filter's state is reset to converged = 1
            # even if it was set to converged = 0 for the current iteration
            # due to missing values
            self.converged = 1

    cdef void migrate_storage(self):
        cdef int inc = 1

        # Forecast: 1 -> 0
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            ccopy(&self.k_endog, &self.forecast[0, 1], &inc, &self.forecast[0, 0], &inc)
            ccopy(&self.k_endog, &self.forecast_error[0, 1], &inc, &self.forecast_error[0, 0], &inc)
            ccopy(&self.k_endog2, &self.forecast_error_cov[0, 0, 1], &inc, &self.forecast_error_cov[0, 0, 0], &inc)

        # Filtered: 1 -> 0
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            ccopy(&self.k_states, &self.filtered_state[0, 1], &inc, &self.filtered_state[0, 0], &inc)
            ccopy(&self.k_states2, &self.filtered_state_cov[0, 0, 1], &inc, &self.filtered_state_cov[0, 0, 0], &inc)

        # Predicted: 1 -> 0
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            ccopy(&self.k_states, &self.predicted_state[0, 1], &inc, &self.predicted_state[0, 0], &inc)
            ccopy(&self.k_states2, &self.predicted_state_cov[0, 0, 1], &inc, &self.predicted_state_cov[0, 0, 0], &inc)

            # Predicted: 2 -> 1
            ccopy(&self.k_states, &self.predicted_state[0, 2], &inc, &self.predicted_state[0, 1], &inc)
            ccopy(&self.k_states2, &self.predicted_state_cov[0, 0, 2], &inc, &self.predicted_state_cov[0, 0, 1], &inc)

## State Space Representation
cdef class dStatespace(object):
    """
    dStatespace(obs, design, obs_intercept, obs_cov, transition, state_intercept, selection, state_cov)

    *See Durbin and Koopman (2012), Chapter 4 for all notation*
    """

    # ### State space representation
    # 
    # $$
    # \begin{align}
    # y_t & = Z_t \alpha_t + d_t + \varepsilon_t \hspace{3em} & \varepsilon_t & \sim N(0, H_t) \\\\
    # \alpha_{t+1} & = T_t \alpha_t + c_t + R_t \eta_t & \eta_t & \sim N(0, Q_t) \\\\
    # & & \alpha_1 & \sim N(a_1, P_1)
    # \end{align}
    # $$
    # 
    # $y_t$ is $p \times 1$  
    # $\varepsilon_t$ is $p \times 1$  
    # $\alpha_t$ is $m \times 1$  
    # $\eta_t$ is $r \times 1$  
    # $t = 1, \dots, T$

    # `nobs` $\equiv T$ is the length of the time-series  
    # `k_endog` $\equiv p$ is dimension of observation space  
    # `k_states` $\equiv m$ is the dimension of the state space  
    # `k_posdef` $\equiv r$ is the dimension of the state shocks  
    # *Old notation: T, n, k, g*
    cdef readonly int nobs, k_endog, k_states, k_posdef
    
    # `obs` $\equiv y_t$ is the **observation vector** $(p \times T)$  
    # `design` $\equiv Z_t$ is the **design vector** $(p \times m \times T)$  
    # `obs_intercept` $\equiv d_t$ is the **observation intercept** $(p \times T)$  
    # `obs_cov` $\equiv H_t$ is the **observation covariance matrix** $(p \times p \times T)$  
    # `transition` $\equiv T_t$ is the **transition matrix** $(m \times m \times T)$  
    # `state_intercept` $\equiv c_t$ is the **state intercept** $(m \times T)$  
    # `selection` $\equiv R_t$ is the **selection matrix** $(m \times r \times T)$  
    # `state_cov` $\equiv Q_t$ is the **state covariance matrix** $(r \times r \times T)$  
    # `selected_state_cov` $\equiv R Q_t R'$ is the **selected state covariance matrix** $(m \times m \times T)$  
    # `initial_state` $\equiv a_1$ is the **initial state mean** $(m \times 1)$  
    # `initial_state_cov` $\equiv P_1$ is the **initial state covariance matrix** $(m \times m)$
    #
    # With the exception of `obs`, these are *optionally* time-varying. If they are instead time-invariant,
    # then the dimension of length $T$ is instead of length $1$.
    #
    # *Note*: the initial vectors' notation 1-indexed as in Durbin and Koopman,
    # but in the recursions below it will be 0-indexed in the Python arrays.
    # 
    # *Old notation: y, -, mu, beta_tt_init, P_tt_init*
    cdef readonly np.float64_t [::1,:] obs, obs_intercept, state_intercept
    cdef readonly np.float64_t [:] initial_state
    cdef readonly np.float64_t [::1,:] initial_state_cov
    # *Old notation: H, R, F, G, Q*, G Q* G'*
    cdef readonly np.float64_t [::1,:,:] design, obs_cov, transition, selection, state_cov, selected_state_cov

    # `missing` is a $(p \times T)$ boolean matrix where a row is a $(p \times 1)$ vector
    # in which the $i$th position is $1$ if $y_{i,t}$ is to be considered a missing value.  
    # *Note:* This is created as the output of np.isnan(obs).
    cdef readonly int [::1,:] missing
    # `nmissing` is an `T \times 0` integer vector holding the number of *missing* observations
    # $p - p_t$
    cdef readonly int [:] nmissing

    # Flag for a time-invariant model, which requires that *all* of the
    # possibly time-varying arrays are time-invariant.
    cdef readonly int time_invariant

    # Flag for initialization.
    cdef readonly int initialized

    # Temporary arrays
    cdef np.float64_t [::1,:] tmp

    # Pointers  
    # *Note*: These are not yet implemented to do anything in this base class
    # but are used in subclasses. Necessary to have them here due to problems
    # with redeclaring the model attribute of KalmanFilter children classes
    cdef np.float64_t * _obs
    cdef np.float64_t * _design
    cdef np.float64_t * _obs_intercept
    cdef np.float64_t * _obs_cov
    cdef np.float64_t * _transition
    cdef np.float64_t * _state_intercept
    cdef np.float64_t * _selection
    cdef np.float64_t * _state_cov
    cdef np.float64_t * _selected_state_cov
    cdef np.float64_t * _initial_state
    cdef np.float64_t * _initial_state_cov

    # ### Initialize state space model
    # *Note*: The initial state and state covariance matrix must be provided.
    def __init__(self,
                 np.float64_t [::1,:]   obs,
                 np.float64_t [::1,:,:] design,
                 np.float64_t [::1,:]   obs_intercept,
                 np.float64_t [::1,:,:] obs_cov,
                 np.float64_t [::1,:,:] transition,
                 np.float64_t [::1,:]   state_intercept,
                 np.float64_t [::1,:,:] selection,
                 np.float64_t [::1,:,:] state_cov):

        # Local variables
        cdef:
            np.npy_intp dim1[1]
            np.npy_intp dim2[2]
            np.npy_intp dim3[3]

        # #### State space representation variables  
        # **Note**: these arrays share data with the versions defined in
        # Python and passed to this constructor, so if they are updated in
        # Python they will also be updated here.
        self.obs = obs
        self.design = design
        self.obs_intercept = obs_intercept
        self.obs_cov = obs_cov
        self.transition = transition
        self.state_intercept = state_intercept
        self.selection = selection
        self.state_cov = state_cov

        # Dimensions
        self.k_endog = obs.shape[0]
        self.k_states = selection.shape[0]
        self.k_posdef = selection.shape[1]
        self.nobs = obs.shape[1]

        # #### Validate matrix dimensions
        #
        # Make sure that the given state-space matrices have consistent sizes
        validate_matrix_shape('design', &self.design.shape[0],
                              self.k_endog, self.k_states, self.nobs)
        validate_vector_shape('observation intercept', &self.obs_intercept.shape[0],
                              self.k_endog, self.nobs)
        validate_matrix_shape('observation covariance matrix', &self.obs_cov.shape[0],
                              self.k_endog, self.k_endog, self.nobs)
        validate_matrix_shape('transition', &self.transition.shape[0],
                              self.k_states, self.k_states, self.nobs)
        validate_vector_shape('state intercept', &self.state_intercept.shape[0],
                              self.k_states, self.nobs)
        validate_matrix_shape('state covariance matrix', &self.state_cov.shape[0],
                              self.k_posdef, self.k_posdef, self.nobs)

        # Check for a time-invariant model
        self.time_invariant = (
            self.design.shape[2] == 1           and
            self.obs_intercept.shape[1] == 1    and
            self.obs_cov.shape[2] == 1          and
            self.transition.shape[2] == 1       and
            self.state_intercept.shape[1] == 1  and
            self.selection.shape[2] == 1        and
            self.state_cov.shape[2] == 1
        )

        # Set the flag for initialization to be false
        self.initialized = False

        # Allocate selected state covariance matrix
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = 1;
        # (we only allocate memory for time-varying array if necessary)
        if self.state_cov.shape[2] > 1 or self.selection.shape[2] > 1:
            dim3[2] = self.nobs
        self.selected_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_FLOAT64, FORTRAN)

        # Handle missing data
        self.missing = np.array(np.isnan(obs), dtype=np.int32, order="F")
        self.nmissing = np.array(np.sum(self.missing, axis=0), dtype=np.int32)

        # Create the temporary array
        # Holds arrays of dimension $(m \times m)$
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.tmp = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)

    # ## Initialize: known values
    #
    # Initialize the filter with specific values, assumed to be known with
    # certainty or else as filled with parameters from a maximum likelihood
    # estimation run.
    def initialize_known(self, np.float64_t [:] initial_state, np.float64_t [::1,:] initial_state_cov):
        """
        initialize_known(initial_state, initial_state_cov)
        """
        validate_vector_shape('inital state', &initial_state.shape[0], self.k_states, None)
        validate_matrix_shape('initial state covariance', &initial_state_cov.shape[0], self.k_states, self.k_states, None)

        self.initial_state = initial_state
        self.initial_state_cov = initial_state_cov

        self.initialized = True

    # ## Initialize: approximate diffuse priors
    #
    # Durbin and Koopman note that this initialization should only be coupled
    # with the standard Kalman filter for "approximate exploratory work" and
    # can lead to "large rounding errors" (p. 125).
    # 
    # *Note:* see Durbin and Koopman section 5.6.1
    def initialize_approximate_diffuse(self, variance=1e2):
        """
        initialize_approximate_diffuse(variance=1e2)
        """
        cdef np.npy_intp dim[1]
        dim[0] = self.k_states
        self.initial_state = np.PyArray_ZEROS(1, dim, np.NPY_FLOAT64, FORTRAN)
        self.initial_state_cov = np.eye(self.k_states, dtype=float).T * variance

        self.initialized = True

    # ## Initialize: stationary process
    # *Note:* see Durbin and Koopman section 5.6.2
    # 
    # TODO improve efficiency with direct BLAS / LAPACK calls
    def initialize_stationary(self):
        """
        initialize_stationary()
        """
        cdef np.npy_intp dim[1]

        # Create selected state covariance matrix
        dselect_state_cov(self.k_states, self.k_posdef,
                                   &self.tmp[0,0],
                                   &self.selection[0,0,0],
                                   &self.state_cov[0,0,0],
                                   &self.selected_state_cov[0,0,0])

        from scipy.linalg import solve_discrete_lyapunov

        dim[0] = self.k_states
        self.initial_state = np.PyArray_ZEROS(1, dim, np.NPY_FLOAT64, FORTRAN)
        self.initial_state_cov = solve_discrete_lyapunov(
            np.array(self.transition[:,:,0], dtype=float),
            np.array(self.selected_state_cov[:,:,0], dtype=float)
        ).T

        self.initialized = True

# ### Selected state covariance matrice
cdef int dselect_state_cov(int k_states, int k_posdef,
                                    np.float64_t * tmp,
                                    np.float64_t * selection,
                                    np.float64_t * state_cov,
                                    np.float64_t * selected_state_cov):
    cdef:
        np.float64_t alpha = 1.0
        np.float64_t beta = 0.0

    # Only need to do something if there is a state covariance matrix
    # (i.e k_posdof == 0)
    if k_posdef > 0:

        # #### Calculate selected state covariance matrix  
        # $Q_t^* = R_t Q_t R_t'$
        # 
        # Combine the selection matrix and the state covariance matrix to get
        # the simplified (but possibly singular) "selected" state covariance
        # matrix (see e.g. Durbin and Koopman p. 43)

        # `tmp0` array used here, dimension $(m \times r)$  

        # $\\#_0 = 1.0 * R_t Q_t$  
        # $(m \times r) = (m \times r) (r \times r)$
        dgemm("N", "N", &k_states, &k_posdef, &k_posdef,
              &alpha, selection, &k_states,
                      state_cov, &k_posdef,
              &beta, tmp, &k_states)
        # $Q_t^* = 1.0 * \\#_0 R_t'$  
        # $(m \times m) = (m \times r) (m \times r)'$
        dgemm("N", "T", &k_states, &k_states, &k_posdef,
              &alpha, tmp, &k_states,
                      selection, &k_states,
              &beta, selected_state_cov, &k_states)

# ## Kalman filter Routines
# 
# The following functions are the workhorse functions for the Kalman filter.
# They represent four distinct but very general phases of the Kalman filtering
# operations.
#
# Their argument is an object of class ?KalmanFilter, which is a stateful
# representation of the recursive filter. For this reason, the below functions
# work almost exclusively through *side-effects* and most return void.
# See the Kalman filter class documentation for further discussion.
#
# They are defined this way so that the actual filtering process can select
# whichever filter type is appropriate for the given time period. For example,
# in the case of state space models with non-stationary components, the filter
# should begin with the exact initial Kalman filter routines but after some
# number of time periods will transition to the conventional Kalman filter
# routines.
#
# Below, `<filter type>` will refer to one of the following:
#
# - `conventional` - the conventional Kalman filter
#
# Other filter types (e.g. `exact_initial`, `augmented`, etc.) may be added in
# the future.
# 
# `forecast_<filter type>` generates the forecast, forecast error $v_t$ and
# forecast error covariance matrix $F_t$  
# `updating_<filter type>` is the updating step of the Kalman filter, and
# generates the filtered state $a_{t|t}$ and covariance matrix $P_{t|t}$  
# `prediction_<filter type>` is the prediction step of the Kalman filter, and
# generates the predicted state $a_{t+1}$ and covariance matrix $P_{t+1}$.
# `loglikelihood_<filter type>` calculates the loglikelihood for $y_t$

# ### Missing Observation Conventional Kalman filter
#
# See Durbin and Koopman (2012) Chapter 4.10
#
# Here k_endog is the same as usual, but the design matrix and observation
# covariance matrix are enforced to be zero matrices, and the loglikelihood
# is defined to be zero.

cdef int dforecast_missing_conventional(dKalmanFilter kfilter):
    cdef int i, j
    cdef int inc = 1

    # #### Forecast for time t  
    # `forecast` $= Z_t a_t + d_t$
    # Just set to zeros, see below (this means if forecasts are required for
    # this part, they must be done in the wrappe)

    # #### Forecast error for time t  
    # It is undefined here, since obs is nan
    for i in range(kfilter.k_endog):
        kfilter._forecast[i] = 0
        kfilter._forecast_error[i] = 0

    # #### Forecast error covariance matrix for time t  
    # $F_t \equiv 0$
    for i in range(kfilter.k_endog):
        for j in range(kfilter.k_endog):
            kfilter._forecast_error_cov[j + i*kfilter.k_endog] = 0

cdef int dupdating_missing_conventional(dKalmanFilter kfilter):
    cdef int inc = 1

    # Simply copy over the input arrays ($a_t, P_t$) to the filtered arrays
    # ($a_{t|t}, P_{t|t}$)
    dcopy(&kfilter.k_states, kfilter._input_state, &inc, kfilter._filtered_state, &inc)
    dcopy(&kfilter.k_states2, kfilter._input_state_cov, &inc, kfilter._filtered_state_cov, &inc)

cdef np.float64_t dinverse_missing_conventional(dKalmanFilter kfilter, np.float64_t determinant)  except *:
    # Since the inverse of the forecast error covariance matrix is not
    # stored, we don't need to fill it (e.g. with NPY_NAN values). Instead,
    # just do a noop here and return a zero determinant ($|0|$).
    return 0.0

cdef np.float64_t dloglikelihood_missing_conventional(dKalmanFilter kfilter, np.float64_t determinant):
    return 0.0

# ### Conventional Kalman filter
#
# The following are the above routines as defined in the conventional Kalman
# filter.
#
# See Durbin and Koopman (2012) Chapter 4

cdef int dforecast_conventional(dKalmanFilter kfilter):

    # Constants
    cdef:
        int inc = 1, ld
        np.float64_t alpha = 1.0
        np.float64_t beta = 0.0
        np.float64_t gamma = -1.0

    # #### Forecast for time t  
    # `forecast` $= Z_t a_t + d_t$
    # 
    # *Note*: $a_t$ is given from the initialization (for $t = 0$) or
    # from the previous iteration of the filter (for $t > 0$).

    # $\\# = d_t$
    dcopy(&kfilter.k_endog, kfilter._obs_intercept, &inc, kfilter._forecast, &inc)
    # `forecast` $= 1.0 * Z_t a_t + 1.0 * \\#$  
    # $(p \times 1) = (p \times m) (m \times 1) + (p \times 1)$
    dgemv("N", &kfilter.k_endog, &kfilter.k_states,
          &alpha, kfilter._design, &kfilter.k_endog,
                  kfilter._input_state, &inc,
          &alpha, kfilter._forecast, &inc)

    # #### Forecast error for time t  
    # `forecast_error` $\equiv v_t = y_t -$ `forecast`

    # $\\# = y_t$
    dcopy(&kfilter.k_endog, kfilter._obs, &inc, kfilter._forecast_error, &inc)
    # $v_t = -1.0 * $ `forecast` $ + \\#$
    # $(p \times 1) = (p \times 1) + (p \times 1)$
    daxpy(&kfilter.k_endog, &gamma, kfilter._forecast, &inc, kfilter._forecast_error, &inc)

    # *Intermediate calculation* (used just below and then once more)  
    # `tmp1` array used here, dimension $(m \times p)$  
    # $\\#_1 = P_t Z_t'$  
    # $(m \times p) = (m \times m) (p \times m)'$
    dgemm("N", "T", &kfilter.k_states, &kfilter.k_endog, &kfilter.k_states,
          &alpha, kfilter._input_state_cov, &kfilter.k_states,
                  kfilter._design, &kfilter.k_endog,
          &beta, kfilter._tmp1, &kfilter.k_states)

    # #### Forecast error covariance matrix for time t  
    # $F_t \equiv Z_t P_t Z_t' + H_t$
    # 
    # *Note*: this and does nothing at all to `forecast_error_cov` if
    # converged == True
    if not kfilter.converged:
        # $\\# = H_t$
        dcopy(&kfilter.k_endog2, kfilter._obs_cov, &inc, kfilter._forecast_error_cov, &inc)

        # $F_t = 1.0 * Z_t \\#_1 + 1.0 * \\#$
        dgemm("N", "N", &kfilter.k_endog, &kfilter.k_endog, &kfilter.k_states,
              &alpha, kfilter._design, &kfilter.k_endog,
                     kfilter._tmp1, &kfilter.k_states,
              &alpha, kfilter._forecast_error_cov, &kfilter.k_endog)

    return 0

cdef int dupdating_conventional(dKalmanFilter kfilter):
    # Constants
    cdef:
        int inc = 1
        np.float64_t alpha = 1.0
        np.float64_t beta = 0.0
        np.float64_t gamma = -1.0
    
    # #### Filtered state for time t
    # $a_{t|t} = a_t + P_t Z_t' F_t^{-1} v_t$  
    # $a_{t|t} = 1.0 * \\#_1 \\#_2 + 1.0 a_t$
    dcopy(&kfilter.k_states, kfilter._input_state, &inc, kfilter._filtered_state, &inc)
    dgemv("N", &kfilter.k_states, &kfilter.k_endog,
          &alpha, kfilter._tmp1, &kfilter.k_states,
                  kfilter._tmp2, &inc,
          &alpha, kfilter._filtered_state, &inc)

    # #### Filtered state covariance for time t
    # $P_{t|t} = P_t - P_t Z_t' F_t^{-1} Z_t P_t$  
    # $P_{t|t} = P_t - \\#_1 \\#_3 P_t$  
    # 
    # *Note*: this and does nothing at all to `filtered_state_cov` if
    # converged == True
    if not kfilter.converged:
        dcopy(&kfilter.k_states2, kfilter._input_state_cov, &inc, kfilter._filtered_state_cov, &inc)

        # `tmp0` array used here, dimension $(m \times m)$  
        # $\\#_0 = 1.0 * \\#_1 \\#_3$  
        # $(m \times m) = (m \times p) (p \times m)$
        dgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_endog,
              &alpha, kfilter._tmp1, &kfilter.k_states,
                      kfilter._tmp3, &kfilter.k_endog,
              &beta, kfilter._tmp0, &kfilter.k_states)

        # $P_{t|t} = - 1.0 * \\# P_t + 1.0 * P_t$  
        # $(m \times m) = (m \times m) (m \times m) + (m \times m)$
        dgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &gamma, kfilter._tmp0, &kfilter.k_states,
                      kfilter._input_state_cov, &kfilter.k_states,
              &alpha, kfilter._filtered_state_cov, &kfilter.k_states)

    return 0

cdef int dprediction_conventional(dKalmanFilter kfilter):

    # Constants
    cdef:
        int inc = 1
        np.float64_t alpha = 1.0
        np.float64_t beta = 0.0
        np.float64_t gamma = -1.0

    # #### Predicted state for time t+1
    # $a_{t+1} = T_t a_{t|t} + c_t$
    dcopy(&kfilter.k_states, kfilter._state_intercept, &inc, kfilter._predicted_state, &inc)
    dgemv("N", &kfilter.k_states, &kfilter.k_states,
          &alpha, kfilter._transition, &kfilter.k_states,
                  kfilter._filtered_state, &inc,
          &alpha, kfilter._predicted_state, &inc)

    # #### Predicted state covariance matrix for time t+1
    # $P_{t+1} = T_t P_{t|t} T_t' + Q_t^*$
    #
    # *Note*: this and does nothing at all to `predicted_state_cov` if
    # converged == True
    if not kfilter.converged:
        dcopy(&kfilter.k_states2, kfilter._selected_state_cov, &inc, kfilter._predicted_state_cov, &inc)
        # `tmp0` array used here, dimension $(m \times m)$  

        # $\\#_0 = T_t P_{t|t} $

        # $(m \times m) = (m \times m) (m \times m)$
        dgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &alpha, kfilter._transition, &kfilter.k_states,
                      kfilter._filtered_state_cov, &kfilter.k_states,
              &beta, kfilter._tmp0, &kfilter.k_states)
        # $P_{t+1} = 1.0 \\#_0 T_t' + 1.0 \\#$  
        # $(m \times m) = (m \times m) (m \times m) + (m \times m)$
        dgemm("N", "T", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &alpha, kfilter._tmp0, &kfilter.k_states,
                      kfilter._transition, &kfilter.k_states,
              &alpha, kfilter._predicted_state_cov, &kfilter.k_states)

    return 0


cdef np.float64_t dloglikelihood_conventional(dKalmanFilter kfilter, np.float64_t determinant):
    # Constants
    cdef:
        np.float64_t loglikelihood
        int inc = 1
        np.float64_t alpha = 1.0
        np.float64_t beta = 0.0

    loglikelihood = -0.5*(kfilter.k_endog*dlog(2*NPY_PI) + dlog(determinant))

    loglikelihood = loglikelihood - 0.5*ddot(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)

    return loglikelihood

# ## Forecast error covariance inversion
#
# The following are routines that can calculate the inverse of the forecast
# error covariance matrix (defined in `forecast_<filter type>`).
#
# These routines are aware of the possibility that the Kalman filter may have
# converged to a steady state, in which case they do not need to perform the
# inversion or calculate the determinant.

cdef np.float64_t dinverse_univariate(dKalmanFilter kfilter, np.float64_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using simple division
    in the case that the observations are univariate.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    # #### Intermediate values
    cdef:
        int inc = 1
        np.float64_t scalar

    # Take the inverse of the forecast error covariance matrix
    if not kfilter.converged:
        determinant = kfilter._forecast_error_cov[0]
    try:
        scalar = 1.0 / kfilter._forecast_error_cov[0]
    except:
        raise np.linalg.LinAlgError('Non-positive-definite forecast error'
                                   ' covariance matrix encountered at'
                                   ' period %d' % kfilter.t)
    kfilter._tmp2[0] = scalar * kfilter._forecast_error[0]
    dcopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    dscal(&kfilter.k_endogstates, &scalar, kfilter._tmp3, &inc)

    return determinant

cdef np.float64_t dfactorize_cholesky(dKalmanFilter kfilter, np.float64_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using a Cholesky
    decomposition. Called by either of the `solve_cholesky` or
    `invert_cholesky` routines.

    Requires a positive definite matrix, but is faster than an LU
    decomposition.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int inc = 1
        int info
        int i

    if not kfilter.converged:
        dcopy(&kfilter.k_endog2, kfilter._forecast_error_cov, &inc, kfilter._forecast_error_fac, &inc)
        dpotrf("U", &kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog, &info)

        if info < 0:
            raise np.linalg.LinAlgError('Illegal value in forecast error'
                                        ' covariance matrix encountered at'
                                        ' period %d' % kfilter.t)
        if info > 0:
            raise np.linalg.LinAlgError('Non-positive-definite forecast error'
                                       ' covariance matrix encountered at'
                                       ' period %d' % kfilter.t)

        # Calculate the determinant (just the squared product of the
        # diagonals, in the Cholesky decomposition case)
        determinant = 1.0
        for i in range(kfilter.k_endog):
            determinant = determinant * kfilter.forecast_error_fac[i, i]
        determinant = determinant**2

    return determinant

cdef np.float64_t dfactorize_lu(dKalmanFilter kfilter, np.float64_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using an LU
    decomposition. Called by either of the `solve_lu` or `invert_lu`
    routines.

    Is slower than a Cholesky decomposition, but does not require a
    positive definite matrix.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int inc = 1
        int info
        int i

    if not kfilter.converged:
        # Perform LU decomposition into `forecast_error_fac`
        dcopy(&kfilter.k_endog2, kfilter._forecast_error_cov, &inc, kfilter._forecast_error_fac, &inc)
        
        dgetrf(&kfilter.k_endog, &kfilter.k_endog,
                        kfilter._forecast_error_fac, &kfilter.k_endog,
                        kfilter._forecast_error_ipiv, &info)

        if info < 0:
            raise np.linalg.LinAlgError('Illegal value in forecast error'
                                        ' covariance matrix encountered at'
                                        ' period %d' % kfilter.t)
        if info > 0:
            raise np.linalg.LinAlgError('Singular forecast error covariance'
                                        ' matrix encountered at period %d' %
                                        kfilter.t)

        # Calculate the determinant (product of the diagonals, but with
        # sign modifications according to the permutation matrix)    
        determinant = 1
        for i in range(kfilter.k_endog):
            if not kfilter._forecast_error_ipiv[i] == i+1:
                determinant *= -1*kfilter.forecast_error_fac[i, i]
            else:
                determinant *= kfilter.forecast_error_fac[i, i]

    return determinant

cdef np.float64_t dinverse_cholesky(dKalmanFilter kfilter, np.float64_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        int i, j
        np.float64_t alpha = 1.0
        np.float64_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = dfactorize_cholesky(kfilter, determinant)

        # Continue taking the inverse
        dpotri("U", &kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog, &info)

        # ?potri only fills in the upper triangle of the symmetric array, and
        # since the ?symm and ?symv routines are not available as of scipy
        # 0.11.0, we can't use them, so we must fill in the lower triangle
        # by hand
        for i in range(kfilter.k_endog):
            for j in range(i):
                kfilter.forecast_error_fac[i,j] = kfilter.forecast_error_fac[j,i]


    # Get `tmp2` and `tmp3` via matrix multiplications

    # `tmp2` array used here, dimension $(p \times 1)$  
    # $\\#_2 = F_t^{-1} v_t$  
    #dsymv("U", &kfilter.k_endog, &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
    #               kfilter._forecast_error, &inc, &beta, kfilter._tmp2, &inc)
    dgemv("N", &kfilter.k_endog, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._forecast_error, &inc,
                   &beta, kfilter._tmp2, &inc)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $\\#_3 = F_t^{-1} Z_t$
    #dsymm("L", "U", &kfilter.k_endog, &kfilter.k_states,
    #               &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
    #                       kfilter._design, &kfilter.k_endog,
    #               &beta, kfilter._tmp3, &kfilter.k_endog)
    dgemm("N", "N", &kfilter.k_endog, &kfilter.k_states, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._design, &kfilter.k_endog,
                   &beta, kfilter._tmp3, &kfilter.k_endog)

    return determinant

cdef np.float64_t dinverse_lu(dKalmanFilter kfilter, np.float64_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        np.float64_t alpha = 1.0
        np.float64_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = dfactorize_lu(kfilter, determinant)

        # Continue taking the inverse
        dgetri(&kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog,
               kfilter._forecast_error_ipiv, kfilter._forecast_error_work, &kfilter.ldwork, &info)

    # Get `tmp2` and `tmp3` via matrix multiplications

    # `tmp2` array used here, dimension $(p \times 1)$  
    # $\\#_2 = F_t^{-1} v_t$  
    dgemv("N", &kfilter.k_endog, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._forecast_error, &inc,
                   &beta, kfilter._tmp2, &inc)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $\\#_3 = F_t^{-1} Z_t$
    dgemm("N", "N", &kfilter.k_endog, &kfilter.k_states, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._design, &kfilter.k_endog,
                   &beta, kfilter._tmp3, &kfilter.k_endog)

    return determinant

cdef np.float64_t dsolve_cholesky(dKalmanFilter kfilter, np.float64_t determinant) except *:
    """
    solve_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = dfactorize_cholesky(kfilter, determinant)

    # Solve the linear systems  
    # `tmp2` array used here, dimension $(p \times 1)$  
    # $F_t \\#_2 = v_t$  
    dcopy(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)
    dpotrs("U", &kfilter.k_endog, &inc, kfilter._forecast_error_fac, &kfilter.k_endog, kfilter._tmp2, &kfilter.k_endog, &info)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $F_t \\#_3 = Z_t$
    dcopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    dpotrs("U", &kfilter.k_endog, &kfilter.k_states, kfilter._forecast_error_fac, &kfilter.k_endog, kfilter._tmp3, &kfilter.k_endog, &info)

    return determinant

cdef np.float64_t dsolve_lu(dKalmanFilter kfilter, np.float64_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        np.float64_t alpha = 1.0
        np.float64_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = dfactorize_lu(kfilter, determinant)

    # Solve the linear systems  
    # `tmp2` array used here, dimension $(p \times 1)$  
    # $F_t \\#_2 = v_t$  
    dcopy(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)
    dgetrs("N", &kfilter.k_endog, &inc, kfilter._forecast_error_fac, &kfilter.k_endog,
                    kfilter._forecast_error_ipiv, kfilter._tmp2, &kfilter.k_endog, &info)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $F_t \\#_3 = Z_t$
    dcopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    dgetrs("N", &kfilter.k_endog, &kfilter.k_states, kfilter._forecast_error_fac, &kfilter.k_endog,
                    kfilter._forecast_error_ipiv, kfilter._tmp3, &kfilter.k_endog, &info)

    return determinant


# ## Kalman filter

cdef class dKalmanFilter(object):
    """
    dKalmanFilter(model, filter=FILTER_CONVENTIONAL, inversion_method=INVERT_UNIVARIATE | SOLVE_CHOLESKY, stability_method=STABILITY_FORCE_SYMMETRY, tolerance=1e-19)

    A representation of the Kalman filter recursions.

    While the filter is mathematically represented as a recursion, it is here
    translated into Python as a stateful iterator.

    Because there are actually several types of Kalman filter depending on the
    state space model of interest, this class only handles the *iteration*
    aspect of filtering, and delegates the actual operations to four general
    workhorse routines, which can be implemented separately for each type of
    Kalman filter.

    In order to maintain a consistent interface, and because these four general
    routines may be quite different across filter types, their argument is only
    the stateful ?KalmanFilter object. Furthermore, in order to allow the
    different types of filter to substitute alternate matrices, this class
    defines a set of pointers to the various state space arrays and the
    filtering output arrays.

    For example, handling missing observations requires not only substituting
    `obs`, `design`, and `obs_cov` matrices, but the new matrices actually have
    different dimensions than the originals. This can be flexibly accomodated
    simply by replacing e.g. the `obs` pointer to the substituted `obs` array
    and replacing `k_endog` for that iteration. Then in the next iteration, when
    the `obs` vector may be missing different elements (or none at all), it can
    again be redefined.

    Each iteration of the filter (see `__next__`) proceeds in a number of
    steps.

    `initialize_object_pointers` initializes pointers to current-iteration
    objects (i.e. the state space arrays and filter output arrays).  

    `initialize_function_pointers` initializes pointers to the appropriate
    Kalman filtering routines (i.e. `forecast_conventional` or
    `forecast_exact_initial`, etc.).  

    `select_arrays` converts the base arrays into "selected" arrays using
    selection matrices. In particular, it handles the state covariance matrix
    and redefined matrices based on missing values.  

    `post_convergence` handles copying arrays from time $t-1$ to time $t$ when
    the Kalman filter has converged and they don't need to be re-calculated.  

    `forecasting` calls the Kalman filter `forcasting_<filter type>` routine

    `inversion` calls the appropriate function to invert the forecast error
    covariance matrix.  

    `updating` calls the Kalman filter `updating_<filter type>` routine

    `loglikelihood` calls the Kalman filter `loglikelihood_<filter type>` routine

    `prediction` calls the Kalman filter `prediction_<filter type>` routine

    `numerical_stability` performs end-of-iteration tasks to improve the numerical
    stability of the filter 

    `check_convergence` checks for convergence of the filter to steady-state.
    """

    # ### Statespace model
    cdef readonly dStatespace model

    # ### Filter parameters
    # Holds the time-iteration state of the filter  
    # *Note*: must be changed using the `seek` method
    cdef readonly int t
    # Holds the tolerance parameter for convergence
    cdef public np.float64_t tolerance
    # Holds the convergence to steady-state status of the filter
    # *Note*: is by default reset each time `seek` is called
    cdef readonly int converged
    cdef readonly int period_converged
    # Holds whether or not the model is time-invariant
    # *Note*: is by default reset each time `seek` is called
    cdef readonly int time_invariant
    # The Kalman filter procedure to use  
    cdef public int filter_method
    # The method by which the terms using the inverse of the forecast
    # error covariance matrix are solved.
    cdef public int inversion_method
    # Methods to improve numerical stability
    cdef public int stability_method
    # Whether or not to conserve memory
    # If True, only stores filtered states and covariance matrices
    cdef readonly int conserve_memory
    # If conserving loglikelihood, the number of periods to "burn"
    # before starting to record the loglikelihood
    cdef readonly int loglikelihood_burn

    # ### Kalman filter properties

    # `loglikelihood` $\equiv \log p(y_t | Y_{t-1})$
    cdef readonly np.float64_t [:] loglikelihood

    # `filtered_state` $\equiv a_{t|t} = E(\alpha_t | Y_t)$ is the **filtered estimator** of the state $(m \times T)$  
    # `predicted_state` $\equiv a_{t+1} = E(\alpha_{t+1} | Y_t)$ is the **one-step ahead predictor** of the state $(m \times T-1)$  
    # `forecast` $\equiv E(y_t|Y_{t-1})$ is the **forecast** of the next observation $(p \times T)$   
    # `forecast_error` $\equiv v_t = y_t - E(y_t|Y_{t-1})$ is the **one-step ahead forecast error** of the next observation $(p \times T)$  
    # 
    # *Note*: Actual values in `filtered_state` will be from 1 to `nobs`+1. Actual
    # values in `predicted_state` will be from 0 to `nobs`+1 because the initialization
    # is copied over to the zeroth entry, and similar for the covariances, below.
    #
    # *Old notation: beta_tt, beta_tt1, y_tt1, eta_tt1*
    cdef readonly np.float64_t [::1,:] filtered_state, predicted_state, forecast, forecast_error

    # `filtered_state_cov` $\equiv P_{t|t} = Var(\alpha_t | Y_t)$ is the **filtered state covariance matrix** $(m \times m \times T)$  
    # `predicted_state_cov` $\equiv P_{t+1} = Var(\alpha_{t+1} | Y_t)$ is the **predicted state covariance matrix** $(m \times m \times T)$  
    # `forecast_error_cov` $\equiv F_t = Var(v_t | Y_{t-1})$ is the **forecast error covariance matrix** $(p \times p \times T)$  
    # 
    # *Old notation: P_tt, P_tt1, f_tt1*
    cdef readonly np.float64_t [::1,:,:] filtered_state_cov, predicted_state_cov, forecast_error_cov

    # ### Steady State Values
    # These matrices are used to hold the converged matrices after the Kalman
    # filter has reached steady-state
    cdef readonly np.float64_t [::1,:] converged_forecast_error_cov
    cdef readonly np.float64_t [::1,:] converged_filtered_state_cov
    cdef readonly np.float64_t [::1,:] converged_predicted_state_cov
    cdef readonly np.float64_t converged_determinant

    # ### Temporary arrays
    # These matrices are used to temporarily hold selected observation vectors,
    # design matrices, and observation covariance matrices in the case of
    # missing data.  
    cdef readonly np.float64_t [:] selected_obs
    # The following are contiguous memory segments which are then used to
    # store the data in the above matrices.
    cdef readonly np.float64_t [:] selected_design
    cdef readonly np.float64_t [:] selected_obs_cov
    # `forecast_error_fac` is a forecast error covariance matrix **factorization** $(p \times p)$.
    # Depending on the method for handling the inverse of the forecast error covariance matrix, it may be:
    # - a Cholesky factorization if `cholesky_solve` is used
    # - an inverse calculated via Cholesky factorization if `cholesky_inverse` is used
    # - an LU factorization if `lu_solve` is used
    # - an inverse calculated via LU factorization if `lu_inverse` is used
    cdef readonly np.float64_t [::1,:] forecast_error_fac
    # `forecast_error_ipiv` holds pivot indices if an LU decomposition is used
    cdef readonly int [:] forecast_error_ipiv
    # `forecast_error_work` is a work array for matrix inversion if an LU
    # decomposition is used
    cdef readonly np.float64_t [::1,:] forecast_error_work
    # These hold the memory allocations of the unnamed temporary arrays
    cdef readonly np.float64_t [::1,:] tmp0, tmp1, tmp3
    cdef readonly np.float64_t [:] tmp2

    # Holds the determinant across calculations (this is done because after
    # convergence, it doesn't need to be re-calculated anymore)
    cdef readonly np.float64_t determinant

    # ### Pointers to current-iteration arrays
    cdef np.float64_t * _obs
    cdef np.float64_t * _design
    cdef np.float64_t * _obs_intercept
    cdef np.float64_t * _obs_cov
    cdef np.float64_t * _transition
    cdef np.float64_t * _state_intercept
    cdef np.float64_t * _selection
    cdef np.float64_t * _state_cov
    cdef np.float64_t * _selected_state_cov
    cdef np.float64_t * _initial_state
    cdef np.float64_t * _initial_state_cov

    cdef np.float64_t * _input_state
    cdef np.float64_t * _input_state_cov

    cdef np.float64_t * _forecast
    cdef np.float64_t * _forecast_error
    cdef np.float64_t * _forecast_error_cov
    cdef np.float64_t * _filtered_state
    cdef np.float64_t * _filtered_state_cov
    cdef np.float64_t * _predicted_state
    cdef np.float64_t * _predicted_state_cov

    cdef np.float64_t * _converged_forecast_error_cov
    cdef np.float64_t * _converged_filtered_state_cov
    cdef np.float64_t * _converged_predicted_state_cov

    cdef np.float64_t * _forecast_error_fac
    cdef int * _forecast_error_ipiv
    cdef np.float64_t * _forecast_error_work

    cdef np.float64_t * _tmp0
    cdef np.float64_t * _tmp1
    cdef np.float64_t * _tmp2
    cdef np.float64_t * _tmp3

    # ### Pointers to current-iteration Kalman filtering functions
    cdef int (*forecasting)(
        dKalmanFilter
    )
    cdef np.float64_t (*inversion)(
        dKalmanFilter, np.float64_t
    ) except *
    cdef int (*updating)(
        dKalmanFilter
    )
    cdef np.float64_t (*calculate_loglikelihood)(
        dKalmanFilter, np.float64_t
    )
    cdef int (*prediction)(
        dKalmanFilter
    )

    # ### Define some constants
    cdef readonly int k_endog, k_states, k_posdef, k_endog2, k_states2, k_endogstates, ldwork
    
    def __init__(self,
                 dStatespace model,
                 int filter_method=FILTER_CONVENTIONAL,
                 int inversion_method=INVERT_UNIVARIATE | SOLVE_CHOLESKY,
                 int stability_method=STABILITY_FORCE_SYMMETRY,
                 int conserve_memory=MEMORY_STORE_ALL,
                 np.float64_t tolerance=1e-19,
                 int loglikelihood_burn=0):
        # Local variables
        cdef:
            np.npy_intp dim1[1]
            np.npy_intp dim2[2]
            np.npy_intp dim3[3]
        cdef int storage

        # Save the model
        self.model = model

        # Initialize filter parameters
        self.tolerance = tolerance
        if not filter_method == FILTER_CONVENTIONAL:
            raise NotImplementedError("Only the conventional Kalman filter is currently implemented")
        self.filter_method = filter_method
        self.inversion_method = inversion_method
        self.stability_method = stability_method
        self.conserve_memory = conserve_memory
        self.loglikelihood_burn = loglikelihood_burn

        # Initialize the constant values
        self.time_invariant = self.model.time_invariant
        self.k_endog = self.model.k_endog
        self.k_states = self.model.k_states
        self.k_posdef = self.model.k_posdef
        self.k_endog2 = self.model.k_endog**2
        self.k_states2 = self.model.k_states**2
        self.k_endogstates = self.model.k_endog * self.model.k_states
        # TODO replace with optimal work array size
        self.ldwork = self.model.k_endog

        # #### Allocate arrays for calculations

        # Arrays for Kalman filter output

        # Forecast
        if self.conserve_memory & MEMORY_NO_FORECAST:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_endog; dim2[1] = storage;
        self.forecast = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        self.forecast_error = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        dim3[0] = self.k_endog; dim3[1] = self.k_endog; dim3[2] = storage;
        self.forecast_error_cov = np.PyArray_ZEROS(3, dim3, np.NPY_FLOAT64, FORTRAN)

        # Filtered
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_states; dim2[1] = storage;
        self.filtered_state = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = storage;
        self.filtered_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_FLOAT64, FORTRAN)

        # Predicted
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_states; dim2[1] = storage+1;
        self.predicted_state = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = storage+1;
        self.predicted_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_FLOAT64, FORTRAN)

        # Likelihood
        if self.conserve_memory & MEMORY_NO_LIKELIHOOD > 0:
            storage = 1
        else:
            storage = self.model.nobs
        dim1[0] = storage
        self.loglikelihood = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT64, FORTRAN)

        # Converged matrices
        dim2[0] = self.k_endog; dim2[1] = self.k_endog;
        self.converged_forecast_error_cov = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        self._converged_forecast_error_cov = &self.converged_forecast_error_cov[0,0]
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.converged_filtered_state_cov = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        self._converged_filtered_state_cov = &self.converged_filtered_state_cov[0,0]
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.converged_predicted_state_cov = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        self._converged_predicted_state_cov = &self.converged_predicted_state_cov[0,0]

        # #### Arrays for temporary calculations
        # *Note*: in math notation below, a $\\#$ will represent a generic
        # temporary array, and a $\\#_i$ will represent a named temporary array.

        # Arrays related to matrix factorizations / inverses
        dim2[0] = self.k_endog; dim2[1] = self.k_endog;
        self.forecast_error_fac = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        self._forecast_error_fac = &self.forecast_error_fac[0,0]
        dim2[0] = self.ldwork; dim2[1] = self.ldwork;
        self.forecast_error_work = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        self._forecast_error_work = &self.forecast_error_work[0,0]
        dim1[0] = self.k_endog;
        self.forecast_error_ipiv = np.PyArray_ZEROS(1, dim1, np.NPY_INT, FORTRAN)
        self._forecast_error_ipiv = &self.forecast_error_ipiv[0]

        # Holds arrays of dimension $(m \times m)$ and $(m \times r)$
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.tmp0 = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        self._tmp0 = &self.tmp0[0, 0]

        # Holds arrays of dimension $(m \times p)$
        dim2[0] = self.k_states; dim2[1] = self.k_endog;
        self.tmp1 = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        self._tmp1 = &self.tmp1[0, 0]

        # Holds arrays of dimension $(p \times 1)$
        dim1[0] = self.k_endog;
        self.tmp2 = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT64, FORTRAN)
        self._tmp2 = &self.tmp2[0]

        # Holds arrays of dimension $(p \times m)$
        dim2[0] = self.k_endog; dim2[1] = self.k_states;
        self.tmp3 = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT64, FORTRAN)
        self._tmp3 = &self.tmp3[0, 0]

        # Arrays for missing data
        dim1[0] = self.k_endog;
        self.selected_obs = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT64, FORTRAN)
        dim1[0] = self.k_endog * self.k_states;
        self.selected_design = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT64, FORTRAN)
        dim1[0] = self.k_endog2;
        self.selected_obs_cov = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT64, FORTRAN)

        # Initialize time and convergence status
        self.t = 0
        self.converged = 0
        self.period_converged = 0

    cpdef set_filter_method(self, int filter_method, int force_reset=True):
        """
        set_filter_method(self, filter_method, force_reset=True)

        Change the filter method.
        """
        self.filter_method = filter_method

    cpdef seek(self, unsigned int t, int reset_convergence = True):
        """
        seek(self, t, reset_convergence = True)

        Change the time-state of the filter

        Is usually called to reset the filter to the beginning.
        """
        if t >= self.model.nobs:
            raise IndexError("Observation index out of range")
        self.t = t

        if reset_convergence:
            self.converged = 0
            self.period_converged = 0

    def __iter__(self):
        return self

    def __call__(self):
        """
        Iterate the filter across the entire set of observations.
        """
        cdef int i

        self.seek(0, True)
        for i in range(self.model.nobs):
            next(self)

    def __next__(self):
        """
        Perform an iteration of the Kalman filter
        """

        # Get time subscript, and stop the iterator if at the end
        if not self.t < self.model.nobs:
            raise StopIteration

        # Initialize pointers to current-iteration objects
        self.initialize_statespace_object_pointers()
        self.initialize_filter_object_pointers()

        # Initialize pointers to appropriate Kalman filtering functions
        self.initialize_function_pointers()

        # Convert base arrays into "selected" arrays  
        # - State covariance matrix? $Q_t \to R_t Q_t R_t`$
        # - Missing values: $y_t \to W_t y_t$, $Z_t \to W_t Z_t$, $H_t \to W_t H_t$
        self.select_state_cov()
        self.select_missing()

        # Post-convergence: copy previous iteration arrays
        self.post_convergence()

        # Form forecasts
        self.forecasting(self)

        # Perform `forecast_error_cov` inversion (or decomposition)
        self.determinant = self.inversion(self, self.determinant)

        # Updating step
        self.updating(self)

        # Retrieve the loglikelihood
        if self.conserve_memory & MEMORY_NO_LIKELIHOOD > 0:
            if self.t == 0:
                self.loglikelihood[0] = 0
            if self.t >= self.loglikelihood_burn:
                self.loglikelihood[0] = self.loglikelihood[0] + self.calculate_loglikelihood(
                    self, self.determinant
                )
        else:
            self.loglikelihood[self.t] = self.calculate_loglikelihood(
                self, self.determinant
            )

        # Prediction step
        self.prediction(self)

        # Aids to numerical stability
        self.numerical_stability()

        # Check for convergence
        self.check_convergence()

        # If conserving memory, migrate storage: t->t-1, t+1->t
        self.migrate_storage()

        # Advance the time
        self.t += 1

    cdef void initialize_statespace_object_pointers(self) except *:
        cdef:
            int t = self.t
        # Indices for possibly time-varying arrays
        cdef:
            int design_t = 0
            int obs_intercept_t = 0
            int obs_cov_t = 0
            int transition_t = 0
            int state_intercept_t = 0
            int selection_t = 0
            int state_cov_t = 0

        # Get indices for possibly time-varying arrays
        if not self.model.time_invariant:
            if self.model.design.shape[2] > 1:             design_t = t
            if self.model.obs_intercept.shape[1] > 1:      obs_intercept_t = t
            if self.model.obs_cov.shape[2] > 1:            obs_cov_t = t
            if self.model.transition.shape[2] > 1:         transition_t = t
            if self.model.state_intercept.shape[1] > 1:    state_intercept_t = t
            if self.model.selection.shape[2] > 1:          selection_t = t
            if self.model.state_cov.shape[2] > 1:          state_cov_t = t

        # Initialize object-level pointers to statespace arrays
        self._obs = &self.model.obs[0, t]
        self._design = &self.model.design[0, 0, design_t]
        self._obs_intercept = &self.model.obs_intercept[0, obs_intercept_t]
        self._obs_cov = &self.model.obs_cov[0, 0, obs_cov_t]
        self._transition = &self.model.transition[0, 0, transition_t]
        self._state_intercept = &self.model.state_intercept[0, state_intercept_t]
        self._selection = &self.model.selection[0, 0, selection_t]
        self._state_cov = &self.model.state_cov[0, 0, state_cov_t]

        # Initialize object-level pointers to initialization
        if not self.model.initialized:
            raise RuntimeError("Statespace model not initialized.")
        self._initial_state = &self.model.initial_state[0]
        self._initial_state_cov = &self.model.initial_state_cov[0,0]

    cdef void initialize_filter_object_pointers(self):
        cdef:
            int t = self.t
            int inc = 1
        # Indices for arrays that may or may not be stored completely
        cdef:
            int forecast_t = t
            int filtered_t = t
            int predicted_t = t
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            forecast_t = 1
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            filtered_t = 1
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            predicted_t = 1

        # Initialize object-level pointers to input arrays
        self._input_state = &self.predicted_state[0, predicted_t]
        self._input_state_cov = &self.predicted_state_cov[0, 0, predicted_t]

        # Copy initialization arrays to input arrays if we're starting the
        # filter
        if t == 0:
            # `predicted_state[:,0]` $= a_1 =$ `initial_state`  
            # `predicted_state_cov[:,:,0]` $= P_1 =$ `initial_state_cov`  
            dcopy(&self.k_states, self._initial_state, &inc, self._input_state, &inc)
            dcopy(&self.k_states2, self._initial_state_cov, &inc, self._input_state_cov, &inc)

        # Initialize object-level pointers to output arrays
        self._forecast = &self.forecast[0, forecast_t]
        self._forecast_error = &self.forecast_error[0, forecast_t]
        self._forecast_error_cov = &self.forecast_error_cov[0, 0, forecast_t]

        self._filtered_state = &self.filtered_state[0, filtered_t]
        self._filtered_state_cov = &self.filtered_state_cov[0, 0, filtered_t]

        self._predicted_state = &self.predicted_state[0, predicted_t+1]
        self._predicted_state_cov = &self.predicted_state_cov[0, 0, predicted_t+1]

    cdef void initialize_function_pointers(self) except *:
        if self.filter_method & FILTER_CONVENTIONAL:
            self.forecasting = dforecast_conventional

            if self.inversion_method & INVERT_UNIVARIATE and self.k_endog == 1:
                self.inversion = dinverse_univariate
            elif self.inversion_method & SOLVE_CHOLESKY:
                self.inversion = dsolve_cholesky
            elif self.inversion_method & SOLVE_LU:
                self.inversion = dsolve_lu
            elif self.inversion_method & INVERT_CHOLESKY:
                self.inversion = dinverse_cholesky
            elif self.inversion_method & INVERT_LU:
                self.inversion = dinverse_lu
            else:
                raise NotImplementedError("Invalid inversion method")

            self.updating = dupdating_conventional
            self.calculate_loglikelihood = dloglikelihood_conventional
            self.prediction = dprediction_conventional

        else:
            raise NotImplementedError("Invalid filtering method")

    cdef void select_state_cov(self):
        cdef int selected_state_cov_t = 0

        # ### Get selected state covariance matrix
        if self.t == 0 or self.model.selected_state_cov.shape[2] > 1:
            selected_state_cov_t = self.t
            self._selected_state_cov = &self.model.selected_state_cov[0, 0, selected_state_cov_t]

            dselect_state_cov(self.k_states, self.k_posdef,
                                       self._tmp0,
                                       self._selection,
                                       self._state_cov,
                                       self._selected_state_cov)
        else:
            self._selected_state_cov = &self.model.selected_state_cov[0, 0, 0]

    cdef void select_missing(self):
        # ### Perform missing selections
        # In Durbin and Koopman (2012), these are represented as matrix
        # multiplications, i.e. $Z_t^* = W_t Z_t$ where $W_t$ is a row
        # selection matrix (it contains a subset of rows of the identity
        # matrix).
        #
        # It's more efficient, though, to just copy over the data directly,
        # which is what is done here. Note that the `selected_*` arrays are
        # defined as single-dimensional, so the assignment indexes below are
        # set such that the arrays can be interpreted by the BLAS and LAPACK
        # functions as two-dimensional, column-major arrays.
        #
        # In the case that all data is missing (e.g. this is what happens in
        # forecasting), we actually set don't change the dimension, but we set
        # the design matrix to the zeros array.
        if self.model.nmissing[self.t] == self.model.k_endog:
            self._select_missing_entire_obs()
        elif self.model.nmissing[self.t] > 0:
            self._select_missing_partial_obs()
        else:
            # Reset dimensions
            self.k_endog = self.model.k_endog
            self.k_endog2 = self.k_endog**2
            self.k_endogstates = self.k_endog * self.k_states

    cdef void _select_missing_entire_obs(self):
        cdef:
            int i, j
        # Mark as not converged so that it does not inappropriately
        # copy over steady state matrices
        self.converged = 0

        # Dimensions are the same as usual (have to reset in case previous
        # obs was partially missing case)
        self.k_endog = self.model.k_endog
        self.k_endog2 = self.k_endog**2
        self.k_endogstates = self.k_endog * self.k_states

        # Design matrix is set to zeros
        for i in range(self.model.k_states):
            for j in range(self.model.k_endog):
                self.selected_design[j + i*self.model.k_endog] = 0.0
        self._design = &self.selected_design[0]

        # Change the forecasting step to set the forecast at the intercept
        # $d_t$, so that the forecast error is $v_t = y_t - d_t$.
        self.forecasting = dforecast_missing_conventional

        # Change the updating step to just copy $a_{t|t} = a_t$ and
        # $P_{t|t} = P_t$
        self.updating = dupdating_missing_conventional

        # Change the inversion step to inverse to nans.
        self.inversion = dinverse_missing_conventional

        # Change the loglikelihood calculation to give zero.
        self.calculate_loglikelihood = dloglikelihood_missing_conventional

        # The prediction step is the same as the conventional Kalman
        # filter

    cdef void _select_missing_partial_obs(self):
        cdef:
            int i, j, k, l
            int inc = 1
            int design_t = 0
            int obs_cov_t = 0
        # Mark as not converged so that it does not inappropriately
        # copy over steady state matrices
        self.converged = 0

        # Set dimensions
        self.k_endog = self.model.k_endog - self.model.nmissing[self.t]
        self.k_endog2 = self.k_endog**2
        self.k_endogstates = self.k_endog * self.k_states

        if self.model.design.shape[2] > 1: design_t = self.t
        if self.model.obs_cov.shape[2] > 1: obs_cov_t = self.t

        k = 0
        for i in range(self.model.k_endog):
            if not self.model.missing[i, self.t]:

                self.selected_obs[k] = self.model.obs[i, self.t]

                # i is rows
                # k is rows
                dcopy(&self.model.k_states,
                      &self.model.design[i, 0, design_t], &self.model.k_endog,
                      &self.selected_design[k], &self.k_endog)

                # i, k is columns
                # j, l is rows
                l = 0
                for j in range(self.model.k_endog):
                    if not self.model.missing[j, self.t]:
                        self.selected_obs_cov[l + k*self.k_endog] = self.model.obs_cov[j, i, obs_cov_t]
                        l += 1
                k += 1
        self._obs = &self.selected_obs[0]
        self._design = &self.selected_design[0]
        self._obs_cov = &self.selected_obs_cov[0]

    cdef void post_convergence(self):
        # TODO this should probably be defined separately for each Kalman filter type - e.g. `post_convergence_conventional`, etc.

        # Constants
        cdef:
            int inc = 1

        if self.converged:
            # $F_t$
            dcopy(&self.k_endog2, self._converged_forecast_error_cov, &inc, self._forecast_error_cov, &inc)
            # $P_{t|t}$
            dcopy(&self.k_states2, self._converged_filtered_state_cov, &inc, self._filtered_state_cov, &inc)
            # $P_t$
            dcopy(&self.k_states2, self._converged_predicted_state_cov, &inc, self._predicted_state_cov, &inc)
            # $|F_t|$
            self.determinant = self.converged_determinant

    cdef void numerical_stability(self):
        cdef int i, j
        cdef int predicted_t = self.t
        cdef np.float64_t value

        if self.conserve_memory & MEMORY_NO_PREDICTED:
            predicted_t = 1

        if self.stability_method & STABILITY_FORCE_SYMMETRY:
            # Enforce symmetry of predicted covariance matrix  
            # $P_{t+1} = 0.5 * (P_{t+1} + P_{t+1}')$  
            # See Grewal (2001), Section 6.3.1.1
            for i in range(self.k_states):
                for j in range(i, self.k_states):
                    value = 0.5 * (
                        self.predicted_state_cov[i,j,predicted_t+1] +
                        self.predicted_state_cov[j,i,predicted_t+1]
                    )
                    self.predicted_state_cov[i,j,predicted_t+1] = value
                    self.predicted_state_cov[j,i,predicted_t+1] = value

    cdef void check_convergence(self):
        # Constants
        cdef:
            int inc = 1
            np.float64_t alpha = 1.0
            np.float64_t beta = 0.0
            np.float64_t gamma = -1.0
        # Indices for arrays that may or may not be stored completely
        cdef:
            int forecast_t = self.t
            int filtered_t = self.t
            int predicted_t = self.t
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            forecast_t = 1
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            filtered_t = 1
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            predicted_t = 1

        if self.time_invariant and not self.converged and self.model.nmissing[self.t] == 0:
            # #### Check for steady-state convergence
            # 
            # `tmp0` array used here, dimension $(m \times m)$  
            # `tmp1` array used here, dimension $(1 \times 1)$  
            dcopy(&self.k_states2, self._input_state_cov, &inc, self._tmp0, &inc)
            daxpy(&self.k_states2, &gamma, self._predicted_state_cov, &inc, self._tmp0, &inc)

            if ddot(&self.k_states2, self._tmp0, &inc, self._tmp0, &inc) < self.tolerance:
                self.converged = 1
                self.period_converged = self.t


            # If we just converged, copy the current iteration matrices to the
            # converged storage
            if self.converged == 1:
                # $F_t$
                dcopy(&self.k_endog2, &self.forecast_error_cov[0, 0, forecast_t], &inc, self._converged_forecast_error_cov, &inc)
                # $P_{t|t}$
                dcopy(&self.k_states2, &self.filtered_state_cov[0, 0, filtered_t], &inc, self._converged_filtered_state_cov, &inc)
                # $P_t$
                dcopy(&self.k_states2, &self.predicted_state_cov[0, 0, predicted_t], &inc, self._converged_predicted_state_cov, &inc)
                # $|F_t|$
                self.converged_determinant = self.determinant
        elif self.period_converged > 0:
            # This is here so that the filter's state is reset to converged = 1
            # even if it was set to converged = 0 for the current iteration
            # due to missing values
            self.converged = 1

    cdef void migrate_storage(self):
        cdef int inc = 1

        # Forecast: 1 -> 0
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            dcopy(&self.k_endog, &self.forecast[0, 1], &inc, &self.forecast[0, 0], &inc)
            dcopy(&self.k_endog, &self.forecast_error[0, 1], &inc, &self.forecast_error[0, 0], &inc)
            dcopy(&self.k_endog2, &self.forecast_error_cov[0, 0, 1], &inc, &self.forecast_error_cov[0, 0, 0], &inc)

        # Filtered: 1 -> 0
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            dcopy(&self.k_states, &self.filtered_state[0, 1], &inc, &self.filtered_state[0, 0], &inc)
            dcopy(&self.k_states2, &self.filtered_state_cov[0, 0, 1], &inc, &self.filtered_state_cov[0, 0, 0], &inc)

        # Predicted: 1 -> 0
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            dcopy(&self.k_states, &self.predicted_state[0, 1], &inc, &self.predicted_state[0, 0], &inc)
            dcopy(&self.k_states2, &self.predicted_state_cov[0, 0, 1], &inc, &self.predicted_state_cov[0, 0, 0], &inc)

            # Predicted: 2 -> 1
            dcopy(&self.k_states, &self.predicted_state[0, 2], &inc, &self.predicted_state[0, 1], &inc)
            dcopy(&self.k_states2, &self.predicted_state_cov[0, 0, 2], &inc, &self.predicted_state_cov[0, 0, 1], &inc)

## State Space Representation
cdef class sStatespace(object):
    """
    sStatespace(obs, design, obs_intercept, obs_cov, transition, state_intercept, selection, state_cov)

    *See Durbin and Koopman (2012), Chapter 4 for all notation*
    """

    # ### State space representation
    # 
    # $$
    # \begin{align}
    # y_t & = Z_t \alpha_t + d_t + \varepsilon_t \hspace{3em} & \varepsilon_t & \sim N(0, H_t) \\\\
    # \alpha_{t+1} & = T_t \alpha_t + c_t + R_t \eta_t & \eta_t & \sim N(0, Q_t) \\\\
    # & & \alpha_1 & \sim N(a_1, P_1)
    # \end{align}
    # $$
    # 
    # $y_t$ is $p \times 1$  
    # $\varepsilon_t$ is $p \times 1$  
    # $\alpha_t$ is $m \times 1$  
    # $\eta_t$ is $r \times 1$  
    # $t = 1, \dots, T$

    # `nobs` $\equiv T$ is the length of the time-series  
    # `k_endog` $\equiv p$ is dimension of observation space  
    # `k_states` $\equiv m$ is the dimension of the state space  
    # `k_posdef` $\equiv r$ is the dimension of the state shocks  
    # *Old notation: T, n, k, g*
    cdef readonly int nobs, k_endog, k_states, k_posdef
    
    # `obs` $\equiv y_t$ is the **observation vector** $(p \times T)$  
    # `design` $\equiv Z_t$ is the **design vector** $(p \times m \times T)$  
    # `obs_intercept` $\equiv d_t$ is the **observation intercept** $(p \times T)$  
    # `obs_cov` $\equiv H_t$ is the **observation covariance matrix** $(p \times p \times T)$  
    # `transition` $\equiv T_t$ is the **transition matrix** $(m \times m \times T)$  
    # `state_intercept` $\equiv c_t$ is the **state intercept** $(m \times T)$  
    # `selection` $\equiv R_t$ is the **selection matrix** $(m \times r \times T)$  
    # `state_cov` $\equiv Q_t$ is the **state covariance matrix** $(r \times r \times T)$  
    # `selected_state_cov` $\equiv R Q_t R'$ is the **selected state covariance matrix** $(m \times m \times T)$  
    # `initial_state` $\equiv a_1$ is the **initial state mean** $(m \times 1)$  
    # `initial_state_cov` $\equiv P_1$ is the **initial state covariance matrix** $(m \times m)$
    #
    # With the exception of `obs`, these are *optionally* time-varying. If they are instead time-invariant,
    # then the dimension of length $T$ is instead of length $1$.
    #
    # *Note*: the initial vectors' notation 1-indexed as in Durbin and Koopman,
    # but in the recursions below it will be 0-indexed in the Python arrays.
    # 
    # *Old notation: y, -, mu, beta_tt_init, P_tt_init*
    cdef readonly np.float32_t [::1,:] obs, obs_intercept, state_intercept
    cdef readonly np.float32_t [:] initial_state
    cdef readonly np.float32_t [::1,:] initial_state_cov
    # *Old notation: H, R, F, G, Q*, G Q* G'*
    cdef readonly np.float32_t [::1,:,:] design, obs_cov, transition, selection, state_cov, selected_state_cov

    # `missing` is a $(p \times T)$ boolean matrix where a row is a $(p \times 1)$ vector
    # in which the $i$th position is $1$ if $y_{i,t}$ is to be considered a missing value.  
    # *Note:* This is created as the output of np.isnan(obs).
    cdef readonly int [::1,:] missing
    # `nmissing` is an `T \times 0` integer vector holding the number of *missing* observations
    # $p - p_t$
    cdef readonly int [:] nmissing

    # Flag for a time-invariant model, which requires that *all* of the
    # possibly time-varying arrays are time-invariant.
    cdef readonly int time_invariant

    # Flag for initialization.
    cdef readonly int initialized

    # Temporary arrays
    cdef np.float32_t [::1,:] tmp

    # Pointers  
    # *Note*: These are not yet implemented to do anything in this base class
    # but are used in subclasses. Necessary to have them here due to problems
    # with redeclaring the model attribute of KalmanFilter children classes
    cdef np.float32_t * _obs
    cdef np.float32_t * _design
    cdef np.float32_t * _obs_intercept
    cdef np.float32_t * _obs_cov
    cdef np.float32_t * _transition
    cdef np.float32_t * _state_intercept
    cdef np.float32_t * _selection
    cdef np.float32_t * _state_cov
    cdef np.float32_t * _selected_state_cov
    cdef np.float32_t * _initial_state
    cdef np.float32_t * _initial_state_cov

    # ### Initialize state space model
    # *Note*: The initial state and state covariance matrix must be provided.
    def __init__(self,
                 np.float32_t [::1,:]   obs,
                 np.float32_t [::1,:,:] design,
                 np.float32_t [::1,:]   obs_intercept,
                 np.float32_t [::1,:,:] obs_cov,
                 np.float32_t [::1,:,:] transition,
                 np.float32_t [::1,:]   state_intercept,
                 np.float32_t [::1,:,:] selection,
                 np.float32_t [::1,:,:] state_cov):

        # Local variables
        cdef:
            np.npy_intp dim1[1]
            np.npy_intp dim2[2]
            np.npy_intp dim3[3]

        # #### State space representation variables  
        # **Note**: these arrays share data with the versions defined in
        # Python and passed to this constructor, so if they are updated in
        # Python they will also be updated here.
        self.obs = obs
        self.design = design
        self.obs_intercept = obs_intercept
        self.obs_cov = obs_cov
        self.transition = transition
        self.state_intercept = state_intercept
        self.selection = selection
        self.state_cov = state_cov

        # Dimensions
        self.k_endog = obs.shape[0]
        self.k_states = selection.shape[0]
        self.k_posdef = selection.shape[1]
        self.nobs = obs.shape[1]

        # #### Validate matrix dimensions
        #
        # Make sure that the given state-space matrices have consistent sizes
        validate_matrix_shape('design', &self.design.shape[0],
                              self.k_endog, self.k_states, self.nobs)
        validate_vector_shape('observation intercept', &self.obs_intercept.shape[0],
                              self.k_endog, self.nobs)
        validate_matrix_shape('observation covariance matrix', &self.obs_cov.shape[0],
                              self.k_endog, self.k_endog, self.nobs)
        validate_matrix_shape('transition', &self.transition.shape[0],
                              self.k_states, self.k_states, self.nobs)
        validate_vector_shape('state intercept', &self.state_intercept.shape[0],
                              self.k_states, self.nobs)
        validate_matrix_shape('state covariance matrix', &self.state_cov.shape[0],
                              self.k_posdef, self.k_posdef, self.nobs)

        # Check for a time-invariant model
        self.time_invariant = (
            self.design.shape[2] == 1           and
            self.obs_intercept.shape[1] == 1    and
            self.obs_cov.shape[2] == 1          and
            self.transition.shape[2] == 1       and
            self.state_intercept.shape[1] == 1  and
            self.selection.shape[2] == 1        and
            self.state_cov.shape[2] == 1
        )

        # Set the flag for initialization to be false
        self.initialized = False

        # Allocate selected state covariance matrix
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = 1;
        # (we only allocate memory for time-varying array if necessary)
        if self.state_cov.shape[2] > 1 or self.selection.shape[2] > 1:
            dim3[2] = self.nobs
        self.selected_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_FLOAT32, FORTRAN)

        # Handle missing data
        self.missing = np.array(np.isnan(obs), dtype=np.int32, order="F")
        self.nmissing = np.array(np.sum(self.missing, axis=0), dtype=np.int32)

        # Create the temporary array
        # Holds arrays of dimension $(m \times m)$
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.tmp = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)

    # ## Initialize: known values
    #
    # Initialize the filter with specific values, assumed to be known with
    # certainty or else as filled with parameters from a maximum likelihood
    # estimation run.
    def initialize_known(self, np.float32_t [:] initial_state, np.float32_t [::1,:] initial_state_cov):
        """
        initialize_known(initial_state, initial_state_cov)
        """
        validate_vector_shape('inital state', &initial_state.shape[0], self.k_states, None)
        validate_matrix_shape('initial state covariance', &initial_state_cov.shape[0], self.k_states, self.k_states, None)

        self.initial_state = initial_state
        self.initial_state_cov = initial_state_cov

        self.initialized = True

    # ## Initialize: approximate diffuse priors
    #
    # Durbin and Koopman note that this initialization should only be coupled
    # with the standard Kalman filter for "approximate exploratory work" and
    # can lead to "large rounding errors" (p. 125).
    # 
    # *Note:* see Durbin and Koopman section 5.6.1
    def initialize_approximate_diffuse(self, variance=1e2):
        """
        initialize_approximate_diffuse(variance=1e2)
        """
        cdef np.npy_intp dim[1]
        dim[0] = self.k_states
        self.initial_state = np.PyArray_ZEROS(1, dim, np.NPY_FLOAT32, FORTRAN)
        self.initial_state_cov = np.eye(self.k_states, dtype=np.float32).T * variance

        self.initialized = True

    # ## Initialize: stationary process
    # *Note:* see Durbin and Koopman section 5.6.2
    # 
    # TODO improve efficiency with direct BLAS / LAPACK calls
    def initialize_stationary(self):
        """
        initialize_stationary()
        """
        cdef np.npy_intp dim[1]

        # Create selected state covariance matrix
        sselect_state_cov(self.k_states, self.k_posdef,
                                   &self.tmp[0,0],
                                   &self.selection[0,0,0],
                                   &self.state_cov[0,0,0],
                                   &self.selected_state_cov[0,0,0])

        from scipy.linalg import solve_discrete_lyapunov

        dim[0] = self.k_states
        self.initial_state = np.PyArray_ZEROS(1, dim, np.NPY_FLOAT32, FORTRAN)
        self.initial_state_cov = solve_discrete_lyapunov(
            np.array(self.transition[:,:,0], dtype=np.float32),
            np.array(self.selected_state_cov[:,:,0], dtype=np.float32)
        ).T

        self.initialized = True

# ### Selected state covariance matrice
cdef int sselect_state_cov(int k_states, int k_posdef,
                                    np.float32_t * tmp,
                                    np.float32_t * selection,
                                    np.float32_t * state_cov,
                                    np.float32_t * selected_state_cov):
    cdef:
        np.float32_t alpha = 1.0
        np.float32_t beta = 0.0

    # Only need to do something if there is a state covariance matrix
    # (i.e k_posdof == 0)
    if k_posdef > 0:

        # #### Calculate selected state covariance matrix  
        # $Q_t^* = R_t Q_t R_t'$
        # 
        # Combine the selection matrix and the state covariance matrix to get
        # the simplified (but possibly singular) "selected" state covariance
        # matrix (see e.g. Durbin and Koopman p. 43)

        # `tmp0` array used here, dimension $(m \times r)$  

        # $\\#_0 = 1.0 * R_t Q_t$  
        # $(m \times r) = (m \times r) (r \times r)$
        sgemm("N", "N", &k_states, &k_posdef, &k_posdef,
              &alpha, selection, &k_states,
                      state_cov, &k_posdef,
              &beta, tmp, &k_states)
        # $Q_t^* = 1.0 * \\#_0 R_t'$  
        # $(m \times m) = (m \times r) (m \times r)'$
        sgemm("N", "T", &k_states, &k_states, &k_posdef,
              &alpha, tmp, &k_states,
                      selection, &k_states,
              &beta, selected_state_cov, &k_states)

# ## Kalman filter Routines
# 
# The following functions are the workhorse functions for the Kalman filter.
# They represent four distinct but very general phases of the Kalman filtering
# operations.
#
# Their argument is an object of class ?KalmanFilter, which is a stateful
# representation of the recursive filter. For this reason, the below functions
# work almost exclusively through *side-effects* and most return void.
# See the Kalman filter class documentation for further discussion.
#
# They are defined this way so that the actual filtering process can select
# whichever filter type is appropriate for the given time period. For example,
# in the case of state space models with non-stationary components, the filter
# should begin with the exact initial Kalman filter routines but after some
# number of time periods will transition to the conventional Kalman filter
# routines.
#
# Below, `<filter type>` will refer to one of the following:
#
# - `conventional` - the conventional Kalman filter
#
# Other filter types (e.g. `exact_initial`, `augmented`, etc.) may be added in
# the future.
# 
# `forecast_<filter type>` generates the forecast, forecast error $v_t$ and
# forecast error covariance matrix $F_t$  
# `updating_<filter type>` is the updating step of the Kalman filter, and
# generates the filtered state $a_{t|t}$ and covariance matrix $P_{t|t}$  
# `prediction_<filter type>` is the prediction step of the Kalman filter, and
# generates the predicted state $a_{t+1}$ and covariance matrix $P_{t+1}$.
# `loglikelihood_<filter type>` calculates the loglikelihood for $y_t$

# ### Missing Observation Conventional Kalman filter
#
# See Durbin and Koopman (2012) Chapter 4.10
#
# Here k_endog is the same as usual, but the design matrix and observation
# covariance matrix are enforced to be zero matrices, and the loglikelihood
# is defined to be zero.

cdef int sforecast_missing_conventional(sKalmanFilter kfilter):
    cdef int i, j
    cdef int inc = 1

    # #### Forecast for time t  
    # `forecast` $= Z_t a_t + d_t$
    # Just set to zeros, see below (this means if forecasts are required for
    # this part, they must be done in the wrappe)

    # #### Forecast error for time t  
    # It is undefined here, since obs is nan
    for i in range(kfilter.k_endog):
        kfilter._forecast[i] = 0
        kfilter._forecast_error[i] = 0

    # #### Forecast error covariance matrix for time t  
    # $F_t \equiv 0$
    for i in range(kfilter.k_endog):
        for j in range(kfilter.k_endog):
            kfilter._forecast_error_cov[j + i*kfilter.k_endog] = 0

cdef int supdating_missing_conventional(sKalmanFilter kfilter):
    cdef int inc = 1

    # Simply copy over the input arrays ($a_t, P_t$) to the filtered arrays
    # ($a_{t|t}, P_{t|t}$)
    scopy(&kfilter.k_states, kfilter._input_state, &inc, kfilter._filtered_state, &inc)
    scopy(&kfilter.k_states2, kfilter._input_state_cov, &inc, kfilter._filtered_state_cov, &inc)

cdef np.float32_t sinverse_missing_conventional(sKalmanFilter kfilter, np.float32_t determinant)  except *:
    # Since the inverse of the forecast error covariance matrix is not
    # stored, we don't need to fill it (e.g. with NPY_NAN values). Instead,
    # just do a noop here and return a zero determinant ($|0|$).
    return 0.0

cdef np.float32_t sloglikelihood_missing_conventional(sKalmanFilter kfilter, np.float32_t determinant):
    return 0.0

# ### Conventional Kalman filter
#
# The following are the above routines as defined in the conventional Kalman
# filter.
#
# See Durbin and Koopman (2012) Chapter 4

cdef int sforecast_conventional(sKalmanFilter kfilter):

    # Constants
    cdef:
        int inc = 1, ld
        np.float32_t alpha = 1.0
        np.float32_t beta = 0.0
        np.float32_t gamma = -1.0

    # #### Forecast for time t  
    # `forecast` $= Z_t a_t + d_t$
    # 
    # *Note*: $a_t$ is given from the initialization (for $t = 0$) or
    # from the previous iteration of the filter (for $t > 0$).

    # $\\# = d_t$
    scopy(&kfilter.k_endog, kfilter._obs_intercept, &inc, kfilter._forecast, &inc)
    # `forecast` $= 1.0 * Z_t a_t + 1.0 * \\#$  
    # $(p \times 1) = (p \times m) (m \times 1) + (p \times 1)$
    sgemv("N", &kfilter.k_endog, &kfilter.k_states,
          &alpha, kfilter._design, &kfilter.k_endog,
                  kfilter._input_state, &inc,
          &alpha, kfilter._forecast, &inc)

    # #### Forecast error for time t  
    # `forecast_error` $\equiv v_t = y_t -$ `forecast`

    # $\\# = y_t$
    scopy(&kfilter.k_endog, kfilter._obs, &inc, kfilter._forecast_error, &inc)
    # $v_t = -1.0 * $ `forecast` $ + \\#$
    # $(p \times 1) = (p \times 1) + (p \times 1)$
    saxpy(&kfilter.k_endog, &gamma, kfilter._forecast, &inc, kfilter._forecast_error, &inc)

    # *Intermediate calculation* (used just below and then once more)  
    # `tmp1` array used here, dimension $(m \times p)$  
    # $\\#_1 = P_t Z_t'$  
    # $(m \times p) = (m \times m) (p \times m)'$
    sgemm("N", "T", &kfilter.k_states, &kfilter.k_endog, &kfilter.k_states,
          &alpha, kfilter._input_state_cov, &kfilter.k_states,
                  kfilter._design, &kfilter.k_endog,
          &beta, kfilter._tmp1, &kfilter.k_states)

    # #### Forecast error covariance matrix for time t  
    # $F_t \equiv Z_t P_t Z_t' + H_t$
    # 
    # *Note*: this and does nothing at all to `forecast_error_cov` if
    # converged == True
    if not kfilter.converged:
        # $\\# = H_t$
        scopy(&kfilter.k_endog2, kfilter._obs_cov, &inc, kfilter._forecast_error_cov, &inc)

        # $F_t = 1.0 * Z_t \\#_1 + 1.0 * \\#$
        sgemm("N", "N", &kfilter.k_endog, &kfilter.k_endog, &kfilter.k_states,
              &alpha, kfilter._design, &kfilter.k_endog,
                     kfilter._tmp1, &kfilter.k_states,
              &alpha, kfilter._forecast_error_cov, &kfilter.k_endog)

    return 0

cdef int supdating_conventional(sKalmanFilter kfilter):
    # Constants
    cdef:
        int inc = 1
        np.float32_t alpha = 1.0
        np.float32_t beta = 0.0
        np.float32_t gamma = -1.0
    
    # #### Filtered state for time t
    # $a_{t|t} = a_t + P_t Z_t' F_t^{-1} v_t$  
    # $a_{t|t} = 1.0 * \\#_1 \\#_2 + 1.0 a_t$
    scopy(&kfilter.k_states, kfilter._input_state, &inc, kfilter._filtered_state, &inc)
    sgemv("N", &kfilter.k_states, &kfilter.k_endog,
          &alpha, kfilter._tmp1, &kfilter.k_states,
                  kfilter._tmp2, &inc,
          &alpha, kfilter._filtered_state, &inc)

    # #### Filtered state covariance for time t
    # $P_{t|t} = P_t - P_t Z_t' F_t^{-1} Z_t P_t$  
    # $P_{t|t} = P_t - \\#_1 \\#_3 P_t$  
    # 
    # *Note*: this and does nothing at all to `filtered_state_cov` if
    # converged == True
    if not kfilter.converged:
        scopy(&kfilter.k_states2, kfilter._input_state_cov, &inc, kfilter._filtered_state_cov, &inc)

        # `tmp0` array used here, dimension $(m \times m)$  
        # $\\#_0 = 1.0 * \\#_1 \\#_3$  
        # $(m \times m) = (m \times p) (p \times m)$
        sgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_endog,
              &alpha, kfilter._tmp1, &kfilter.k_states,
                      kfilter._tmp3, &kfilter.k_endog,
              &beta, kfilter._tmp0, &kfilter.k_states)

        # $P_{t|t} = - 1.0 * \\# P_t + 1.0 * P_t$  
        # $(m \times m) = (m \times m) (m \times m) + (m \times m)$
        sgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &gamma, kfilter._tmp0, &kfilter.k_states,
                      kfilter._input_state_cov, &kfilter.k_states,
              &alpha, kfilter._filtered_state_cov, &kfilter.k_states)

    return 0

cdef int sprediction_conventional(sKalmanFilter kfilter):

    # Constants
    cdef:
        int inc = 1
        np.float32_t alpha = 1.0
        np.float32_t beta = 0.0
        np.float32_t gamma = -1.0

    # #### Predicted state for time t+1
    # $a_{t+1} = T_t a_{t|t} + c_t$
    scopy(&kfilter.k_states, kfilter._state_intercept, &inc, kfilter._predicted_state, &inc)
    sgemv("N", &kfilter.k_states, &kfilter.k_states,
          &alpha, kfilter._transition, &kfilter.k_states,
                  kfilter._filtered_state, &inc,
          &alpha, kfilter._predicted_state, &inc)

    # #### Predicted state covariance matrix for time t+1
    # $P_{t+1} = T_t P_{t|t} T_t' + Q_t^*$
    #
    # *Note*: this and does nothing at all to `predicted_state_cov` if
    # converged == True
    if not kfilter.converged:
        scopy(&kfilter.k_states2, kfilter._selected_state_cov, &inc, kfilter._predicted_state_cov, &inc)
        # `tmp0` array used here, dimension $(m \times m)$  

        # $\\#_0 = T_t P_{t|t} $

        # $(m \times m) = (m \times m) (m \times m)$
        sgemm("N", "N", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &alpha, kfilter._transition, &kfilter.k_states,
                      kfilter._filtered_state_cov, &kfilter.k_states,
              &beta, kfilter._tmp0, &kfilter.k_states)
        # $P_{t+1} = 1.0 \\#_0 T_t' + 1.0 \\#$  
        # $(m \times m) = (m \times m) (m \times m) + (m \times m)$
        sgemm("N", "T", &kfilter.k_states, &kfilter.k_states, &kfilter.k_states,
              &alpha, kfilter._tmp0, &kfilter.k_states,
                      kfilter._transition, &kfilter.k_states,
              &alpha, kfilter._predicted_state_cov, &kfilter.k_states)

    return 0


cdef np.float32_t sloglikelihood_conventional(sKalmanFilter kfilter, np.float32_t determinant):
    # Constants
    cdef:
        np.float32_t loglikelihood
        int inc = 1
        np.float32_t alpha = 1.0
        np.float32_t beta = 0.0

    loglikelihood = -0.5*(kfilter.k_endog*dlog(2*NPY_PI) + dlog(determinant))

    loglikelihood = loglikelihood - 0.5*sdot(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)

    return loglikelihood

# ## Forecast error covariance inversion
#
# The following are routines that can calculate the inverse of the forecast
# error covariance matrix (defined in `forecast_<filter type>`).
#
# These routines are aware of the possibility that the Kalman filter may have
# converged to a steady state, in which case they do not need to perform the
# inversion or calculate the determinant.

cdef np.float32_t sinverse_univariate(sKalmanFilter kfilter, np.float32_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using simple division
    in the case that the observations are univariate.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    # #### Intermediate values
    cdef:
        int inc = 1
        np.float32_t scalar

    # Take the inverse of the forecast error covariance matrix
    if not kfilter.converged:
        determinant = kfilter._forecast_error_cov[0]
    try:
        scalar = 1.0 / kfilter._forecast_error_cov[0]
    except:
        raise np.linalg.LinAlgError('Non-positive-definite forecast error'
                                   ' covariance matrix encountered at'
                                   ' period %d' % kfilter.t)
    kfilter._tmp2[0] = scalar * kfilter._forecast_error[0]
    scopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    sscal(&kfilter.k_endogstates, &scalar, kfilter._tmp3, &inc)

    return determinant

cdef np.float32_t sfactorize_cholesky(sKalmanFilter kfilter, np.float32_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using a Cholesky
    decomposition. Called by either of the `solve_cholesky` or
    `invert_cholesky` routines.

    Requires a positive definite matrix, but is faster than an LU
    decomposition.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int inc = 1
        int info
        int i

    if not kfilter.converged:
        scopy(&kfilter.k_endog2, kfilter._forecast_error_cov, &inc, kfilter._forecast_error_fac, &inc)
        spotrf("U", &kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog, &info)

        if info < 0:
            raise np.linalg.LinAlgError('Illegal value in forecast error'
                                        ' covariance matrix encountered at'
                                        ' period %d' % kfilter.t)
        if info > 0:
            raise np.linalg.LinAlgError('Non-positive-definite forecast error'
                                       ' covariance matrix encountered at'
                                       ' period %d' % kfilter.t)

        # Calculate the determinant (just the squared product of the
        # diagonals, in the Cholesky decomposition case)
        determinant = 1.0
        for i in range(kfilter.k_endog):
            determinant = determinant * kfilter.forecast_error_fac[i, i]
        determinant = determinant**2

    return determinant

cdef np.float32_t sfactorize_lu(sKalmanFilter kfilter, np.float32_t determinant) except *:
    """
    Factorize the forecast error covariance matrix using an LU
    decomposition. Called by either of the `solve_lu` or `invert_lu`
    routines.

    Is slower than a Cholesky decomposition, but does not require a
    positive definite matrix.

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int inc = 1
        int info
        int i

    if not kfilter.converged:
        # Perform LU decomposition into `forecast_error_fac`
        scopy(&kfilter.k_endog2, kfilter._forecast_error_cov, &inc, kfilter._forecast_error_fac, &inc)
        
        sgetrf(&kfilter.k_endog, &kfilter.k_endog,
                        kfilter._forecast_error_fac, &kfilter.k_endog,
                        kfilter._forecast_error_ipiv, &info)

        if info < 0:
            raise np.linalg.LinAlgError('Illegal value in forecast error'
                                        ' covariance matrix encountered at'
                                        ' period %d' % kfilter.t)
        if info > 0:
            raise np.linalg.LinAlgError('Singular forecast error covariance'
                                        ' matrix encountered at period %d' %
                                        kfilter.t)

        # Calculate the determinant (product of the diagonals, but with
        # sign modifications according to the permutation matrix)    
        determinant = 1
        for i in range(kfilter.k_endog):
            if not kfilter._forecast_error_ipiv[i] == i+1:
                determinant *= -1*kfilter.forecast_error_fac[i, i]
            else:
                determinant *= kfilter.forecast_error_fac[i, i]

    return determinant

cdef np.float32_t sinverse_cholesky(sKalmanFilter kfilter, np.float32_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        int i, j
        np.float32_t alpha = 1.0
        np.float32_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = sfactorize_cholesky(kfilter, determinant)

        # Continue taking the inverse
        spotri("U", &kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog, &info)

        # ?potri only fills in the upper triangle of the symmetric array, and
        # since the ?symm and ?symv routines are not available as of scipy
        # 0.11.0, we can't use them, so we must fill in the lower triangle
        # by hand
        for i in range(kfilter.k_endog):
            for j in range(i):
                kfilter.forecast_error_fac[i,j] = kfilter.forecast_error_fac[j,i]


    # Get `tmp2` and `tmp3` via matrix multiplications

    # `tmp2` array used here, dimension $(p \times 1)$  
    # $\\#_2 = F_t^{-1} v_t$  
    #ssymv("U", &kfilter.k_endog, &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
    #               kfilter._forecast_error, &inc, &beta, kfilter._tmp2, &inc)
    sgemv("N", &kfilter.k_endog, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._forecast_error, &inc,
                   &beta, kfilter._tmp2, &inc)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $\\#_3 = F_t^{-1} Z_t$
    #ssymm("L", "U", &kfilter.k_endog, &kfilter.k_states,
    #               &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
    #                       kfilter._design, &kfilter.k_endog,
    #               &beta, kfilter._tmp3, &kfilter.k_endog)
    sgemm("N", "N", &kfilter.k_endog, &kfilter.k_states, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._design, &kfilter.k_endog,
                   &beta, kfilter._tmp3, &kfilter.k_endog)

    return determinant

cdef np.float32_t sinverse_lu(sKalmanFilter kfilter, np.float32_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        np.float32_t alpha = 1.0
        np.float32_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = sfactorize_lu(kfilter, determinant)

        # Continue taking the inverse
        sgetri(&kfilter.k_endog, kfilter._forecast_error_fac, &kfilter.k_endog,
               kfilter._forecast_error_ipiv, kfilter._forecast_error_work, &kfilter.ldwork, &info)

    # Get `tmp2` and `tmp3` via matrix multiplications

    # `tmp2` array used here, dimension $(p \times 1)$  
    # $\\#_2 = F_t^{-1} v_t$  
    sgemv("N", &kfilter.k_endog, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._forecast_error, &inc,
                   &beta, kfilter._tmp2, &inc)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $\\#_3 = F_t^{-1} Z_t$
    sgemm("N", "N", &kfilter.k_endog, &kfilter.k_states, &kfilter.k_endog,
                   &alpha, kfilter._forecast_error_fac, &kfilter.k_endog,
                           kfilter._design, &kfilter.k_endog,
                   &beta, kfilter._tmp3, &kfilter.k_endog)

    return determinant

cdef np.float32_t ssolve_cholesky(sKalmanFilter kfilter, np.float32_t determinant) except *:
    """
    solve_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = sfactorize_cholesky(kfilter, determinant)

    # Solve the linear systems  
    # `tmp2` array used here, dimension $(p \times 1)$  
    # $F_t \\#_2 = v_t$  
    scopy(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)
    spotrs("U", &kfilter.k_endog, &inc, kfilter._forecast_error_fac, &kfilter.k_endog, kfilter._tmp2, &kfilter.k_endog, &info)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $F_t \\#_3 = Z_t$
    scopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    spotrs("U", &kfilter.k_endog, &kfilter.k_states, kfilter._forecast_error_fac, &kfilter.k_endog, kfilter._tmp3, &kfilter.k_endog, &info)

    return determinant

cdef np.float32_t ssolve_lu(sKalmanFilter kfilter, np.float32_t determinant) except *:
    """
    inverse_cholesky(self, determinant)

    If the model has converged to a steady-state, this is a NOOP and simply
    returns the determinant that was passed in.
    """
    cdef:
        int info
        int inc = 1
        np.float32_t alpha = 1.0
        np.float32_t beta = 0.0

    if not kfilter.converged:
        # Perform the Cholesky decomposition and get the determinant
        determinant = sfactorize_lu(kfilter, determinant)

    # Solve the linear systems  
    # `tmp2` array used here, dimension $(p \times 1)$  
    # $F_t \\#_2 = v_t$  
    scopy(&kfilter.k_endog, kfilter._forecast_error, &inc, kfilter._tmp2, &inc)
    sgetrs("N", &kfilter.k_endog, &inc, kfilter._forecast_error_fac, &kfilter.k_endog,
                    kfilter._forecast_error_ipiv, kfilter._tmp2, &kfilter.k_endog, &info)

    # `tmp3` array used here, dimension $(p \times m)$  
    # $F_t \\#_3 = Z_t$
    scopy(&kfilter.k_endogstates, kfilter._design, &inc, kfilter._tmp3, &inc)
    sgetrs("N", &kfilter.k_endog, &kfilter.k_states, kfilter._forecast_error_fac, &kfilter.k_endog,
                    kfilter._forecast_error_ipiv, kfilter._tmp3, &kfilter.k_endog, &info)

    return determinant


# ## Kalman filter

cdef class sKalmanFilter(object):
    """
    sKalmanFilter(model, filter=FILTER_CONVENTIONAL, inversion_method=INVERT_UNIVARIATE | SOLVE_CHOLESKY, stability_method=STABILITY_FORCE_SYMMETRY, tolerance=1e-19)

    A representation of the Kalman filter recursions.

    While the filter is mathematically represented as a recursion, it is here
    translated into Python as a stateful iterator.

    Because there are actually several types of Kalman filter depending on the
    state space model of interest, this class only handles the *iteration*
    aspect of filtering, and delegates the actual operations to four general
    workhorse routines, which can be implemented separately for each type of
    Kalman filter.

    In order to maintain a consistent interface, and because these four general
    routines may be quite different across filter types, their argument is only
    the stateful ?KalmanFilter object. Furthermore, in order to allow the
    different types of filter to substitute alternate matrices, this class
    defines a set of pointers to the various state space arrays and the
    filtering output arrays.

    For example, handling missing observations requires not only substituting
    `obs`, `design`, and `obs_cov` matrices, but the new matrices actually have
    different dimensions than the originals. This can be flexibly accomodated
    simply by replacing e.g. the `obs` pointer to the substituted `obs` array
    and replacing `k_endog` for that iteration. Then in the next iteration, when
    the `obs` vector may be missing different elements (or none at all), it can
    again be redefined.

    Each iteration of the filter (see `__next__`) proceeds in a number of
    steps.

    `initialize_object_pointers` initializes pointers to current-iteration
    objects (i.e. the state space arrays and filter output arrays).  

    `initialize_function_pointers` initializes pointers to the appropriate
    Kalman filtering routines (i.e. `forecast_conventional` or
    `forecast_exact_initial`, etc.).  

    `select_arrays` converts the base arrays into "selected" arrays using
    selection matrices. In particular, it handles the state covariance matrix
    and redefined matrices based on missing values.  

    `post_convergence` handles copying arrays from time $t-1$ to time $t$ when
    the Kalman filter has converged and they don't need to be re-calculated.  

    `forecasting` calls the Kalman filter `forcasting_<filter type>` routine

    `inversion` calls the appropriate function to invert the forecast error
    covariance matrix.  

    `updating` calls the Kalman filter `updating_<filter type>` routine

    `loglikelihood` calls the Kalman filter `loglikelihood_<filter type>` routine

    `prediction` calls the Kalman filter `prediction_<filter type>` routine

    `numerical_stability` performs end-of-iteration tasks to improve the numerical
    stability of the filter 

    `check_convergence` checks for convergence of the filter to steady-state.
    """

    # ### Statespace model
    cdef readonly sStatespace model

    # ### Filter parameters
    # Holds the time-iteration state of the filter  
    # *Note*: must be changed using the `seek` method
    cdef readonly int t
    # Holds the tolerance parameter for convergence
    cdef public np.float64_t tolerance
    # Holds the convergence to steady-state status of the filter
    # *Note*: is by default reset each time `seek` is called
    cdef readonly int converged
    cdef readonly int period_converged
    # Holds whether or not the model is time-invariant
    # *Note*: is by default reset each time `seek` is called
    cdef readonly int time_invariant
    # The Kalman filter procedure to use  
    cdef public int filter_method
    # The method by which the terms using the inverse of the forecast
    # error covariance matrix are solved.
    cdef public int inversion_method
    # Methods to improve numerical stability
    cdef public int stability_method
    # Whether or not to conserve memory
    # If True, only stores filtered states and covariance matrices
    cdef readonly int conserve_memory
    # If conserving loglikelihood, the number of periods to "burn"
    # before starting to record the loglikelihood
    cdef readonly int loglikelihood_burn

    # ### Kalman filter properties

    # `loglikelihood` $\equiv \log p(y_t | Y_{t-1})$
    cdef readonly np.float32_t [:] loglikelihood

    # `filtered_state` $\equiv a_{t|t} = E(\alpha_t | Y_t)$ is the **filtered estimator** of the state $(m \times T)$  
    # `predicted_state` $\equiv a_{t+1} = E(\alpha_{t+1} | Y_t)$ is the **one-step ahead predictor** of the state $(m \times T-1)$  
    # `forecast` $\equiv E(y_t|Y_{t-1})$ is the **forecast** of the next observation $(p \times T)$   
    # `forecast_error` $\equiv v_t = y_t - E(y_t|Y_{t-1})$ is the **one-step ahead forecast error** of the next observation $(p \times T)$  
    # 
    # *Note*: Actual values in `filtered_state` will be from 1 to `nobs`+1. Actual
    # values in `predicted_state` will be from 0 to `nobs`+1 because the initialization
    # is copied over to the zeroth entry, and similar for the covariances, below.
    #
    # *Old notation: beta_tt, beta_tt1, y_tt1, eta_tt1*
    cdef readonly np.float32_t [::1,:] filtered_state, predicted_state, forecast, forecast_error

    # `filtered_state_cov` $\equiv P_{t|t} = Var(\alpha_t | Y_t)$ is the **filtered state covariance matrix** $(m \times m \times T)$  
    # `predicted_state_cov` $\equiv P_{t+1} = Var(\alpha_{t+1} | Y_t)$ is the **predicted state covariance matrix** $(m \times m \times T)$  
    # `forecast_error_cov` $\equiv F_t = Var(v_t | Y_{t-1})$ is the **forecast error covariance matrix** $(p \times p \times T)$  
    # 
    # *Old notation: P_tt, P_tt1, f_tt1*
    cdef readonly np.float32_t [::1,:,:] filtered_state_cov, predicted_state_cov, forecast_error_cov

    # ### Steady State Values
    # These matrices are used to hold the converged matrices after the Kalman
    # filter has reached steady-state
    cdef readonly np.float32_t [::1,:] converged_forecast_error_cov
    cdef readonly np.float32_t [::1,:] converged_filtered_state_cov
    cdef readonly np.float32_t [::1,:] converged_predicted_state_cov
    cdef readonly np.float32_t converged_determinant

    # ### Temporary arrays
    # These matrices are used to temporarily hold selected observation vectors,
    # design matrices, and observation covariance matrices in the case of
    # missing data.  
    cdef readonly np.float32_t [:] selected_obs
    # The following are contiguous memory segments which are then used to
    # store the data in the above matrices.
    cdef readonly np.float32_t [:] selected_design
    cdef readonly np.float32_t [:] selected_obs_cov
    # `forecast_error_fac` is a forecast error covariance matrix **factorization** $(p \times p)$.
    # Depending on the method for handling the inverse of the forecast error covariance matrix, it may be:
    # - a Cholesky factorization if `cholesky_solve` is used
    # - an inverse calculated via Cholesky factorization if `cholesky_inverse` is used
    # - an LU factorization if `lu_solve` is used
    # - an inverse calculated via LU factorization if `lu_inverse` is used
    cdef readonly np.float32_t [::1,:] forecast_error_fac
    # `forecast_error_ipiv` holds pivot indices if an LU decomposition is used
    cdef readonly int [:] forecast_error_ipiv
    # `forecast_error_work` is a work array for matrix inversion if an LU
    # decomposition is used
    cdef readonly np.float32_t [::1,:] forecast_error_work
    # These hold the memory allocations of the unnamed temporary arrays
    cdef readonly np.float32_t [::1,:] tmp0, tmp1, tmp3
    cdef readonly np.float32_t [:] tmp2

    # Holds the determinant across calculations (this is done because after
    # convergence, it doesn't need to be re-calculated anymore)
    cdef readonly np.float32_t determinant

    # ### Pointers to current-iteration arrays
    cdef np.float32_t * _obs
    cdef np.float32_t * _design
    cdef np.float32_t * _obs_intercept
    cdef np.float32_t * _obs_cov
    cdef np.float32_t * _transition
    cdef np.float32_t * _state_intercept
    cdef np.float32_t * _selection
    cdef np.float32_t * _state_cov
    cdef np.float32_t * _selected_state_cov
    cdef np.float32_t * _initial_state
    cdef np.float32_t * _initial_state_cov

    cdef np.float32_t * _input_state
    cdef np.float32_t * _input_state_cov

    cdef np.float32_t * _forecast
    cdef np.float32_t * _forecast_error
    cdef np.float32_t * _forecast_error_cov
    cdef np.float32_t * _filtered_state
    cdef np.float32_t * _filtered_state_cov
    cdef np.float32_t * _predicted_state
    cdef np.float32_t * _predicted_state_cov

    cdef np.float32_t * _converged_forecast_error_cov
    cdef np.float32_t * _converged_filtered_state_cov
    cdef np.float32_t * _converged_predicted_state_cov

    cdef np.float32_t * _forecast_error_fac
    cdef int * _forecast_error_ipiv
    cdef np.float32_t * _forecast_error_work

    cdef np.float32_t * _tmp0
    cdef np.float32_t * _tmp1
    cdef np.float32_t * _tmp2
    cdef np.float32_t * _tmp3

    # ### Pointers to current-iteration Kalman filtering functions
    cdef int (*forecasting)(
        sKalmanFilter
    )
    cdef np.float32_t (*inversion)(
        sKalmanFilter, np.float32_t
    ) except *
    cdef int (*updating)(
        sKalmanFilter
    )
    cdef np.float32_t (*calculate_loglikelihood)(
        sKalmanFilter, np.float32_t
    )
    cdef int (*prediction)(
        sKalmanFilter
    )

    # ### Define some constants
    cdef readonly int k_endog, k_states, k_posdef, k_endog2, k_states2, k_endogstates, ldwork
    
    def __init__(self,
                 sStatespace model,
                 int filter_method=FILTER_CONVENTIONAL,
                 int inversion_method=INVERT_UNIVARIATE | SOLVE_CHOLESKY,
                 int stability_method=STABILITY_FORCE_SYMMETRY,
                 int conserve_memory=MEMORY_STORE_ALL,
                 np.float64_t tolerance=1e-19,
                 int loglikelihood_burn=0):
        # Local variables
        cdef:
            np.npy_intp dim1[1]
            np.npy_intp dim2[2]
            np.npy_intp dim3[3]
        cdef int storage

        # Save the model
        self.model = model

        # Initialize filter parameters
        self.tolerance = tolerance
        if not filter_method == FILTER_CONVENTIONAL:
            raise NotImplementedError("Only the conventional Kalman filter is currently implemented")
        self.filter_method = filter_method
        self.inversion_method = inversion_method
        self.stability_method = stability_method
        self.conserve_memory = conserve_memory
        self.loglikelihood_burn = loglikelihood_burn

        # Initialize the constant values
        self.time_invariant = self.model.time_invariant
        self.k_endog = self.model.k_endog
        self.k_states = self.model.k_states
        self.k_posdef = self.model.k_posdef
        self.k_endog2 = self.model.k_endog**2
        self.k_states2 = self.model.k_states**2
        self.k_endogstates = self.model.k_endog * self.model.k_states
        # TODO replace with optimal work array size
        self.ldwork = self.model.k_endog

        # #### Allocate arrays for calculations

        # Arrays for Kalman filter output

        # Forecast
        if self.conserve_memory & MEMORY_NO_FORECAST:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_endog; dim2[1] = storage;
        self.forecast = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        self.forecast_error = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        dim3[0] = self.k_endog; dim3[1] = self.k_endog; dim3[2] = storage;
        self.forecast_error_cov = np.PyArray_ZEROS(3, dim3, np.NPY_FLOAT32, FORTRAN)

        # Filtered
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_states; dim2[1] = storage;
        self.filtered_state = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = storage;
        self.filtered_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_FLOAT32, FORTRAN)

        # Predicted
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            storage = 2
        else:
            storage = self.model.nobs
        dim2[0] = self.k_states; dim2[1] = storage+1;
        self.predicted_state = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        dim3[0] = self.k_states; dim3[1] = self.k_states; dim3[2] = storage+1;
        self.predicted_state_cov = np.PyArray_ZEROS(3, dim3, np.NPY_FLOAT32, FORTRAN)

        # Likelihood
        if self.conserve_memory & MEMORY_NO_LIKELIHOOD > 0:
            storage = 1
        else:
            storage = self.model.nobs
        dim1[0] = storage
        self.loglikelihood = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT32, FORTRAN)

        # Converged matrices
        dim2[0] = self.k_endog; dim2[1] = self.k_endog;
        self.converged_forecast_error_cov = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        self._converged_forecast_error_cov = &self.converged_forecast_error_cov[0,0]
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.converged_filtered_state_cov = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        self._converged_filtered_state_cov = &self.converged_filtered_state_cov[0,0]
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.converged_predicted_state_cov = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        self._converged_predicted_state_cov = &self.converged_predicted_state_cov[0,0]

        # #### Arrays for temporary calculations
        # *Note*: in math notation below, a $\\#$ will represent a generic
        # temporary array, and a $\\#_i$ will represent a named temporary array.

        # Arrays related to matrix factorizations / inverses
        dim2[0] = self.k_endog; dim2[1] = self.k_endog;
        self.forecast_error_fac = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        self._forecast_error_fac = &self.forecast_error_fac[0,0]
        dim2[0] = self.ldwork; dim2[1] = self.ldwork;
        self.forecast_error_work = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        self._forecast_error_work = &self.forecast_error_work[0,0]
        dim1[0] = self.k_endog;
        self.forecast_error_ipiv = np.PyArray_ZEROS(1, dim1, np.NPY_INT, FORTRAN)
        self._forecast_error_ipiv = &self.forecast_error_ipiv[0]

        # Holds arrays of dimension $(m \times m)$ and $(m \times r)$
        dim2[0] = self.k_states; dim2[1] = self.k_states;
        self.tmp0 = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        self._tmp0 = &self.tmp0[0, 0]

        # Holds arrays of dimension $(m \times p)$
        dim2[0] = self.k_states; dim2[1] = self.k_endog;
        self.tmp1 = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        self._tmp1 = &self.tmp1[0, 0]

        # Holds arrays of dimension $(p \times 1)$
        dim1[0] = self.k_endog;
        self.tmp2 = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT32, FORTRAN)
        self._tmp2 = &self.tmp2[0]

        # Holds arrays of dimension $(p \times m)$
        dim2[0] = self.k_endog; dim2[1] = self.k_states;
        self.tmp3 = np.PyArray_ZEROS(2, dim2, np.NPY_FLOAT32, FORTRAN)
        self._tmp3 = &self.tmp3[0, 0]

        # Arrays for missing data
        dim1[0] = self.k_endog;
        self.selected_obs = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT32, FORTRAN)
        dim1[0] = self.k_endog * self.k_states;
        self.selected_design = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT32, FORTRAN)
        dim1[0] = self.k_endog2;
        self.selected_obs_cov = np.PyArray_ZEROS(1, dim1, np.NPY_FLOAT32, FORTRAN)

        # Initialize time and convergence status
        self.t = 0
        self.converged = 0
        self.period_converged = 0

    cpdef set_filter_method(self, int filter_method, int force_reset=True):
        """
        set_filter_method(self, filter_method, force_reset=True)

        Change the filter method.
        """
        self.filter_method = filter_method

    cpdef seek(self, unsigned int t, int reset_convergence = True):
        """
        seek(self, t, reset_convergence = True)

        Change the time-state of the filter

        Is usually called to reset the filter to the beginning.
        """
        if t >= self.model.nobs:
            raise IndexError("Observation index out of range")
        self.t = t

        if reset_convergence:
            self.converged = 0
            self.period_converged = 0

    def __iter__(self):
        return self

    def __call__(self):
        """
        Iterate the filter across the entire set of observations.
        """
        cdef int i

        self.seek(0, True)
        for i in range(self.model.nobs):
            next(self)

    def __next__(self):
        """
        Perform an iteration of the Kalman filter
        """

        # Get time subscript, and stop the iterator if at the end
        if not self.t < self.model.nobs:
            raise StopIteration

        # Initialize pointers to current-iteration objects
        self.initialize_statespace_object_pointers()
        self.initialize_filter_object_pointers()

        # Initialize pointers to appropriate Kalman filtering functions
        self.initialize_function_pointers()

        # Convert base arrays into "selected" arrays  
        # - State covariance matrix? $Q_t \to R_t Q_t R_t`$
        # - Missing values: $y_t \to W_t y_t$, $Z_t \to W_t Z_t$, $H_t \to W_t H_t$
        self.select_state_cov()
        self.select_missing()

        # Post-convergence: copy previous iteration arrays
        self.post_convergence()

        # Form forecasts
        self.forecasting(self)

        # Perform `forecast_error_cov` inversion (or decomposition)
        self.determinant = self.inversion(self, self.determinant)

        # Updating step
        self.updating(self)

        # Retrieve the loglikelihood
        if self.conserve_memory & MEMORY_NO_LIKELIHOOD > 0:
            if self.t == 0:
                self.loglikelihood[0] = 0
            if self.t >= self.loglikelihood_burn:
                self.loglikelihood[0] = self.loglikelihood[0] + self.calculate_loglikelihood(
                    self, self.determinant
                )
        else:
            self.loglikelihood[self.t] = self.calculate_loglikelihood(
                self, self.determinant
            )

        # Prediction step
        self.prediction(self)

        # Aids to numerical stability
        self.numerical_stability()

        # Check for convergence
        self.check_convergence()

        # If conserving memory, migrate storage: t->t-1, t+1->t
        self.migrate_storage()

        # Advance the time
        self.t += 1

    cdef void initialize_statespace_object_pointers(self) except *:
        cdef:
            int t = self.t
        # Indices for possibly time-varying arrays
        cdef:
            int design_t = 0
            int obs_intercept_t = 0
            int obs_cov_t = 0
            int transition_t = 0
            int state_intercept_t = 0
            int selection_t = 0
            int state_cov_t = 0

        # Get indices for possibly time-varying arrays
        if not self.model.time_invariant:
            if self.model.design.shape[2] > 1:             design_t = t
            if self.model.obs_intercept.shape[1] > 1:      obs_intercept_t = t
            if self.model.obs_cov.shape[2] > 1:            obs_cov_t = t
            if self.model.transition.shape[2] > 1:         transition_t = t
            if self.model.state_intercept.shape[1] > 1:    state_intercept_t = t
            if self.model.selection.shape[2] > 1:          selection_t = t
            if self.model.state_cov.shape[2] > 1:          state_cov_t = t

        # Initialize object-level pointers to statespace arrays
        self._obs = &self.model.obs[0, t]
        self._design = &self.model.design[0, 0, design_t]
        self._obs_intercept = &self.model.obs_intercept[0, obs_intercept_t]
        self._obs_cov = &self.model.obs_cov[0, 0, obs_cov_t]
        self._transition = &self.model.transition[0, 0, transition_t]
        self._state_intercept = &self.model.state_intercept[0, state_intercept_t]
        self._selection = &self.model.selection[0, 0, selection_t]
        self._state_cov = &self.model.state_cov[0, 0, state_cov_t]

        # Initialize object-level pointers to initialization
        if not self.model.initialized:
            raise RuntimeError("Statespace model not initialized.")
        self._initial_state = &self.model.initial_state[0]
        self._initial_state_cov = &self.model.initial_state_cov[0,0]

    cdef void initialize_filter_object_pointers(self):
        cdef:
            int t = self.t
            int inc = 1
        # Indices for arrays that may or may not be stored completely
        cdef:
            int forecast_t = t
            int filtered_t = t
            int predicted_t = t
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            forecast_t = 1
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            filtered_t = 1
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            predicted_t = 1

        # Initialize object-level pointers to input arrays
        self._input_state = &self.predicted_state[0, predicted_t]
        self._input_state_cov = &self.predicted_state_cov[0, 0, predicted_t]

        # Copy initialization arrays to input arrays if we're starting the
        # filter
        if t == 0:
            # `predicted_state[:,0]` $= a_1 =$ `initial_state`  
            # `predicted_state_cov[:,:,0]` $= P_1 =$ `initial_state_cov`  
            scopy(&self.k_states, self._initial_state, &inc, self._input_state, &inc)
            scopy(&self.k_states2, self._initial_state_cov, &inc, self._input_state_cov, &inc)

        # Initialize object-level pointers to output arrays
        self._forecast = &self.forecast[0, forecast_t]
        self._forecast_error = &self.forecast_error[0, forecast_t]
        self._forecast_error_cov = &self.forecast_error_cov[0, 0, forecast_t]

        self._filtered_state = &self.filtered_state[0, filtered_t]
        self._filtered_state_cov = &self.filtered_state_cov[0, 0, filtered_t]

        self._predicted_state = &self.predicted_state[0, predicted_t+1]
        self._predicted_state_cov = &self.predicted_state_cov[0, 0, predicted_t+1]

    cdef void initialize_function_pointers(self) except *:
        if self.filter_method & FILTER_CONVENTIONAL:
            self.forecasting = sforecast_conventional

            if self.inversion_method & INVERT_UNIVARIATE and self.k_endog == 1:
                self.inversion = sinverse_univariate
            elif self.inversion_method & SOLVE_CHOLESKY:
                self.inversion = ssolve_cholesky
            elif self.inversion_method & SOLVE_LU:
                self.inversion = ssolve_lu
            elif self.inversion_method & INVERT_CHOLESKY:
                self.inversion = sinverse_cholesky
            elif self.inversion_method & INVERT_LU:
                self.inversion = sinverse_lu
            else:
                raise NotImplementedError("Invalid inversion method")

            self.updating = supdating_conventional
            self.calculate_loglikelihood = sloglikelihood_conventional
            self.prediction = sprediction_conventional

        else:
            raise NotImplementedError("Invalid filtering method")

    cdef void select_state_cov(self):
        cdef int selected_state_cov_t = 0

        # ### Get selected state covariance matrix
        if self.t == 0 or self.model.selected_state_cov.shape[2] > 1:
            selected_state_cov_t = self.t
            self._selected_state_cov = &self.model.selected_state_cov[0, 0, selected_state_cov_t]

            sselect_state_cov(self.k_states, self.k_posdef,
                                       self._tmp0,
                                       self._selection,
                                       self._state_cov,
                                       self._selected_state_cov)
        else:
            self._selected_state_cov = &self.model.selected_state_cov[0, 0, 0]

    cdef void select_missing(self):
        # ### Perform missing selections
        # In Durbin and Koopman (2012), these are represented as matrix
        # multiplications, i.e. $Z_t^* = W_t Z_t$ where $W_t$ is a row
        # selection matrix (it contains a subset of rows of the identity
        # matrix).
        #
        # It's more efficient, though, to just copy over the data directly,
        # which is what is done here. Note that the `selected_*` arrays are
        # defined as single-dimensional, so the assignment indexes below are
        # set such that the arrays can be interpreted by the BLAS and LAPACK
        # functions as two-dimensional, column-major arrays.
        #
        # In the case that all data is missing (e.g. this is what happens in
        # forecasting), we actually set don't change the dimension, but we set
        # the design matrix to the zeros array.
        if self.model.nmissing[self.t] == self.model.k_endog:
            self._select_missing_entire_obs()
        elif self.model.nmissing[self.t] > 0:
            self._select_missing_partial_obs()
        else:
            # Reset dimensions
            self.k_endog = self.model.k_endog
            self.k_endog2 = self.k_endog**2
            self.k_endogstates = self.k_endog * self.k_states

    cdef void _select_missing_entire_obs(self):
        cdef:
            int i, j
        # Mark as not converged so that it does not inappropriately
        # copy over steady state matrices
        self.converged = 0

        # Dimensions are the same as usual (have to reset in case previous
        # obs was partially missing case)
        self.k_endog = self.model.k_endog
        self.k_endog2 = self.k_endog**2
        self.k_endogstates = self.k_endog * self.k_states

        # Design matrix is set to zeros
        for i in range(self.model.k_states):
            for j in range(self.model.k_endog):
                self.selected_design[j + i*self.model.k_endog] = 0.0
        self._design = &self.selected_design[0]

        # Change the forecasting step to set the forecast at the intercept
        # $d_t$, so that the forecast error is $v_t = y_t - d_t$.
        self.forecasting = sforecast_missing_conventional

        # Change the updating step to just copy $a_{t|t} = a_t$ and
        # $P_{t|t} = P_t$
        self.updating = supdating_missing_conventional

        # Change the inversion step to inverse to nans.
        self.inversion = sinverse_missing_conventional

        # Change the loglikelihood calculation to give zero.
        self.calculate_loglikelihood = sloglikelihood_missing_conventional

        # The prediction step is the same as the conventional Kalman
        # filter

    cdef void _select_missing_partial_obs(self):
        cdef:
            int i, j, k, l
            int inc = 1
            int design_t = 0
            int obs_cov_t = 0
        # Mark as not converged so that it does not inappropriately
        # copy over steady state matrices
        self.converged = 0

        # Set dimensions
        self.k_endog = self.model.k_endog - self.model.nmissing[self.t]
        self.k_endog2 = self.k_endog**2
        self.k_endogstates = self.k_endog * self.k_states

        if self.model.design.shape[2] > 1: design_t = self.t
        if self.model.obs_cov.shape[2] > 1: obs_cov_t = self.t

        k = 0
        for i in range(self.model.k_endog):
            if not self.model.missing[i, self.t]:

                self.selected_obs[k] = self.model.obs[i, self.t]

                # i is rows
                # k is rows
                scopy(&self.model.k_states,
                      &self.model.design[i, 0, design_t], &self.model.k_endog,
                      &self.selected_design[k], &self.k_endog)

                # i, k is columns
                # j, l is rows
                l = 0
                for j in range(self.model.k_endog):
                    if not self.model.missing[j, self.t]:
                        self.selected_obs_cov[l + k*self.k_endog] = self.model.obs_cov[j, i, obs_cov_t]
                        l += 1
                k += 1
        self._obs = &self.selected_obs[0]
        self._design = &self.selected_design[0]
        self._obs_cov = &self.selected_obs_cov[0]

    cdef void post_convergence(self):
        # TODO this should probably be defined separately for each Kalman filter type - e.g. `post_convergence_conventional`, etc.

        # Constants
        cdef:
            int inc = 1

        if self.converged:
            # $F_t$
            scopy(&self.k_endog2, self._converged_forecast_error_cov, &inc, self._forecast_error_cov, &inc)
            # $P_{t|t}$
            scopy(&self.k_states2, self._converged_filtered_state_cov, &inc, self._filtered_state_cov, &inc)
            # $P_t$
            scopy(&self.k_states2, self._converged_predicted_state_cov, &inc, self._predicted_state_cov, &inc)
            # $|F_t|$
            self.determinant = self.converged_determinant

    cdef void numerical_stability(self):
        cdef int i, j
        cdef int predicted_t = self.t
        cdef np.float32_t value

        if self.conserve_memory & MEMORY_NO_PREDICTED:
            predicted_t = 1

        if self.stability_method & STABILITY_FORCE_SYMMETRY:
            # Enforce symmetry of predicted covariance matrix  
            # $P_{t+1} = 0.5 * (P_{t+1} + P_{t+1}')$  
            # See Grewal (2001), Section 6.3.1.1
            for i in range(self.k_states):
                for j in range(i, self.k_states):
                    value = 0.5 * (
                        self.predicted_state_cov[i,j,predicted_t+1] +
                        self.predicted_state_cov[j,i,predicted_t+1]
                    )
                    self.predicted_state_cov[i,j,predicted_t+1] = value
                    self.predicted_state_cov[j,i,predicted_t+1] = value

    cdef void check_convergence(self):
        # Constants
        cdef:
            int inc = 1
            np.float32_t alpha = 1.0
            np.float32_t beta = 0.0
            np.float32_t gamma = -1.0
        # Indices for arrays that may or may not be stored completely
        cdef:
            int forecast_t = self.t
            int filtered_t = self.t
            int predicted_t = self.t
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            forecast_t = 1
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            filtered_t = 1
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            predicted_t = 1

        if self.time_invariant and not self.converged and self.model.nmissing[self.t] == 0:
            # #### Check for steady-state convergence
            # 
            # `tmp0` array used here, dimension $(m \times m)$  
            # `tmp1` array used here, dimension $(1 \times 1)$  
            scopy(&self.k_states2, self._input_state_cov, &inc, self._tmp0, &inc)
            saxpy(&self.k_states2, &gamma, self._predicted_state_cov, &inc, self._tmp0, &inc)

            if sdot(&self.k_states2, self._tmp0, &inc, self._tmp0, &inc) < self.tolerance:
                self.converged = 1
                self.period_converged = self.t


            # If we just converged, copy the current iteration matrices to the
            # converged storage
            if self.converged == 1:
                # $F_t$
                scopy(&self.k_endog2, &self.forecast_error_cov[0, 0, forecast_t], &inc, self._converged_forecast_error_cov, &inc)
                # $P_{t|t}$
                scopy(&self.k_states2, &self.filtered_state_cov[0, 0, filtered_t], &inc, self._converged_filtered_state_cov, &inc)
                # $P_t$
                scopy(&self.k_states2, &self.predicted_state_cov[0, 0, predicted_t], &inc, self._converged_predicted_state_cov, &inc)
                # $|F_t|$
                self.converged_determinant = self.determinant
        elif self.period_converged > 0:
            # This is here so that the filter's state is reset to converged = 1
            # even if it was set to converged = 0 for the current iteration
            # due to missing values
            self.converged = 1

    cdef void migrate_storage(self):
        cdef int inc = 1

        # Forecast: 1 -> 0
        if self.conserve_memory & MEMORY_NO_FORECAST > 0:
            scopy(&self.k_endog, &self.forecast[0, 1], &inc, &self.forecast[0, 0], &inc)
            scopy(&self.k_endog, &self.forecast_error[0, 1], &inc, &self.forecast_error[0, 0], &inc)
            scopy(&self.k_endog2, &self.forecast_error_cov[0, 0, 1], &inc, &self.forecast_error_cov[0, 0, 0], &inc)

        # Filtered: 1 -> 0
        if self.conserve_memory & MEMORY_NO_FILTERED > 0:
            scopy(&self.k_states, &self.filtered_state[0, 1], &inc, &self.filtered_state[0, 0], &inc)
            scopy(&self.k_states2, &self.filtered_state_cov[0, 0, 1], &inc, &self.filtered_state_cov[0, 0, 0], &inc)

        # Predicted: 1 -> 0
        if self.conserve_memory & MEMORY_NO_PREDICTED > 0:
            scopy(&self.k_states, &self.predicted_state[0, 1], &inc, &self.predicted_state[0, 0], &inc)
            scopy(&self.k_states2, &self.predicted_state_cov[0, 0, 1], &inc, &self.predicted_state_cov[0, 0, 0], &inc)

            # Predicted: 2 -> 1
            scopy(&self.k_states, &self.predicted_state[0, 2], &inc, &self.predicted_state[0, 1], &inc)
            scopy(&self.k_states2, &self.predicted_state_cov[0, 0, 2], &inc, &self.predicted_state_cov[0, 0, 1], &inc)
