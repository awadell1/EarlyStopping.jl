module EarlyStopping

using Dates
using Statistics
import Base.+

export StoppingCriterion,
    Never,
    OutOfBounds,
    NotANumber, # deprecated
    TimeLimit,
    GL,
    NumberSinceBest,
    Patience,
    UP,
    PQ,
    NumberLimit,
    Threshold,
    Disjunction,
    criteria,
    stopping_time,
    EarlyStopper,
    done!,
    message,
    needs_training_losses,
    needs_loss

include("api.jl")
include("criteria.jl")
include("disjunction.jl")
include("stopping_time.jl")
include("object_oriented_api.jl")

end # module
