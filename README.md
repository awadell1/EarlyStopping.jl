# EarlyStopping.jl

| Linux | Coverage |
| :-----------: | :------: |
| [![Build status](https://github.com/ablaom/EarlyStopping.jl/workflows/CI/badge.svg)](https://github.com/ablaom/EarlyStopping.jl/actions)| [![codecov.io](http://codecov.io/github/ablaom/EarlyStopping.jl/coverage.svg?branch=master)](http://codecov.io/github/ablaom/EarlyStopping.jl?branch=master) |

A small package for applying early stopping criteria to
loss-generating iterative algorithms, with a view
to training and optimizing machine learning models.

The basis of [IterationControl.jl](https://github.com/ablaom/IterationControl.jl), 
a package externally controlling iterative algorithms.

Includes the stopping criteria surveyed in [Prechelt, Lutz
(1998)](https://link.springer.com/chapter/10.1007%2F3-540-49430-8_3):
"Early Stopping - But When?", in *Neural Networks: Tricks of the
Trade*, ed. G. Orr, Springer.

## Installation

```julia
using Pkg
Pkg.add("EarlyStopping")
```

## Sample usage

The `EarlyStopper` objects defined in this package consume a sequence
of numbers called *losses* generated by some external algorithm -
generally the training loss or out-of-sample loss of some iterative
statistical model - and decide when those losses have dropped
sufficiently to warrant terminating the algorithm. A number of
commonly applied *stopping criteria*, listed under
[Criteria](#criteria) below, are provided out-of-the-box.

Here's an example of using an `EarlyStopper` object to check against
two of these criteria (either triggering the stop):

```julia
using EarlyStopping

stopper = EarlyStopper(Patience(2), NotANumber()) # multiple criteria
done!(stopper, 0.123) # false
done!(stopper, 0.234) # false
done!(stopper, 0.345) # true

julia> message(stopper)
"Early stop triggered by Patience(2) stopping criterion. "
```

One may force an `EarlyStopper` to report its evolving state:

```julia
losses = [10.0, 11.0, 10.0, 11.0, 12.0, 10.0];
stopper = EarlyStopper(Patience(2), verbosity=1);

for loss in losses
    done!(stopper, loss) && break
end
```

```
[ Info: loss: 10.0       state: (loss = 10.0, n_increases = 0)
[ Info: loss: 11.0       state: (loss = 11.0, n_increases = 1)
[ Info: loss: 10.0       state: (loss = 10.0, n_increases = 0)
[ Info: loss: 11.0       state: (loss = 11.0, n_increases = 1)
[ Info: loss: 12.0       state: (loss = 12.0, n_increases = 2)
```

The "object-oriented" interface demonstrated here is not code-optimized but
will suffice for the majority of use-cases. For performant code, use
the functional interface described under [Implementing new
criteria](#implementing-new-criteria) below.


## Criteria

To list all stopping criterion, do `subtypes(StoppingCriterion)`. Each
subtype `T` has a detailed doc-string queried with `?T` at the
REPL. Here is a short summary:


criterion             | description                                           | notation in Prechelt
----------------------|-------------------------------------------------------|---------------------
`Never()`             | Never stop                                            |
`NotANumber()`        | Stop when `NaN` encountered                           |
`TimeLimit(t=0.5)`    | Stop after `t` hours                                  |
`CountLimit(n=100)`  | Stop after `n` loss updates (excl. "training losses") |
`Threshold(value=0.0)`| Stop when `loss < value`                              | 
`GL(alpha=2.0)`       | Stop after "Generalization Loss" exceeds `alpha`      | ``GL_α``
`PQ(alpha=0.75, k=5)` | Stop after "Progress-modified GL" exceeds `alpha`     | ``PQ_α``
`Patience(n=5)`       | Stop after `n` consecutive loss increases             | ``UP_s``
`Disjunction(c...)`   | Stop when any of the criteria `c` apply               |


## Criteria tracking both training and out-of-sample losses

For criteria tracking both an "out-of-sample" loss and a "training"
loss (eg, stopping criterion of type `PQ`), specify `training=true` if
the update is for training, as in

    done!(stopper, 0.123, training=true)

In these cases, the out-of-sample update must always come after the
corresponding training update. Multiple training updates may precede
the out-of-sample update, as in the following example:

```julia
criterion = PQ(alpha=2.0, k=2)
needs_in_and_out_of_sample(criterion) # true

stopper = EarlyStopper(criterion)

done!(stopper, 9.5, training=true) # false
done!(stopper, 9.3, training=true) # false
done!(stopper, 10.0) # false

done!(stopper, 9.3, training=true) # false
done!(stopper, 9.1, training=true) # false
done!(stopper, 8.9, training=true) # false
done!(stopper, 8.0) # false

done!(stopper, 8.3, training=true) # false
done!(stopper, 8.4, training=true) # false
done!(stopper, 9.0) # true
```

**Important.** If there is no distinction between in and out-of-sample
losses, then any criterion can be applied, *and in that case* `training=true`
*is never specified* (regardless of the actual interpretation of the
losses being tracked).


## Stopping times

To determine the stopping time for an iterator `losses`, use
`stopping_time(criterion, losses)`. This is useful for debugging new
criteria (see below). If the iterator terminates without a stop, `0`
is returned.

```julia
julia> stopping_time(NotANumber(), [10.0, 3.0, NaN, 4.0])
3

julia> stopping_time(Patience(3), [10.0, 3.0, 4.0, 5.0], verbosity=1)
[ Info: loss updates: 1
[ Info: state: (loss = 10.0, n_increases = 0)
[ Info: loss updates: 2
[ Info: state: (loss = 3.0, n_increases = 0)
[ Info: loss updates: 3
[ Info: state: (loss = 4.0, n_increases = 1)
[ Info: loss updates: 4
[ Info: state: (loss = 5.0, n_increases = 2)
0
```

If the losses include both training and out-of-sample losses as
described above, pass an extra `Bool` vector marking the training
losses with `true`, as in

```julia
stopping_time(PQ(),
              [0.123, 0.321, 0.52, 0.55, 0.56, 0.58],
              [true, true, false, true, true, false])
```

## Implementing new criteria

To implement a new stopping criterion, one must:

- Define a new `struct` for the criterion, which must subtype
`StoppingCriterion`.

- Overload methods `update` and `done` for the new type.

- Optionally overload methods `message`.

- Optionally overload `update_training` and the trait
  `needs_in_and_out_of_sample`.

We demonstrate this with a simplified version of the
[code](/src/criteria.jl) for `Patience`:


### Defining the new type

```julia
using EarlyStopping

mutable struct Patience <: StoppingCriterion
    n::Int
end
Patience(; n=5) = Patience(n)
```

### Overloading `update` and `done`

All information to be "remembered" must passed around in an object
called `state` below, which is the return value of `update` (and
`update_training`). The `update` function has two methods - one for
initialization, without a `state` argument, and one for all subsequent
loss updates, which requires the `state` returned by the preceding
`update` (or `update_training`) call:

```julia
import EarlyStopping: update, done

update(criterion::Patience, loss) = (loss=loss, n_increases=0) # state

function update(criterion::Patience, loss, state)
    old_loss, n = state
    if loss > old_loss
        n += 1
    else
        n = 0
    end
    return (loss=loss, n_increases=n) # state
end
```

The `done` method returns `true` or `false` depending on the `state`:

```julia
done(criterion::Patience, state) = state.n_increases == criterion.n
```

### Optional methods

The final message of an `EarlyStopper` is generated by a `message`
method for `StoppingCriterion`. Here is the fallback (which does not
use `state`):

```julia
EarlyStopping.message(criteria::StoppingCriterion, state)
    = "Early stop triggered by $criterion stopping criterion. "
```

The optional `update_training` methods (two for each criterion) have
the same signature as the `update` methods above. Refer to the `PQ`
[code](/src/criteria.jl) for an example.

If a stopping criterion requires one or more `update_training` calls
per `update` call to work, you should overload the trait
`needs_in_and_out_of_sample` for that type, as in this example from
the source code:

```julia
EarlyStopping.needs_in_and_out_of_sample(::Type{<:PQ}) = true
```
