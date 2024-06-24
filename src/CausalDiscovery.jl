module CausalDiscovery
using Reexport

#include("Autumn/Autumn.jl")
#reexport using .Autumn

# include("CISC/CISC.jl")
# include("CISC.jl")
# include("MCMC.jl/model.jl")
# include("MCMC.jl/grammar.jl")
include("synthesis/cisc/cisc.jl")
@reexport using .Cisc
# export generate_observations_custom_input_w_state, parse_and_map_objects, get_initialized_m


end # module
