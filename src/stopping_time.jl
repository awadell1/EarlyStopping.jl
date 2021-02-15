_update(::Val{false}, args...) = update(args...)
_update(::Val{true}, args...) = update_training(args...)
_getindex(is_training::Nothing, s) = false
_getindex(is_training, s) = is_training[s]

function stopping_time(criterion, losses, is_training; verbosity=0)

    t_stop = 0 # meaning no stop
    t = 0 # counts regular `update` calls but ignores `update_training` calls
    s = 0 # counter for iteration over `losses`

    global state

    for loss in losses
        s += 1
        _is_training = _getindex(is_training, s)
        state = if s == 1
            _update(Val(_is_training), criterion, loss)
        else
            _update(Val(_is_training), criterion, loss, state)
        end
        _is_training || (t += 1)
        verbosity < 1 || begin
            @info "loss updates: $t"
            @info "state: $state"
        end
        if !_is_training && done(criterion, state)
            t_stop = t
            break
        end
    end

    return t_stop

end

stopping_time(criterion, losses; kwargs...) =
    stopping_time(criterion, losses, nothing; kwargs...)
