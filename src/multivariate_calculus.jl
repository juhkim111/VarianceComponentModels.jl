# module MultivariateCalculus
using SparseArrays
export vech, trilind, triuind,
  commutation, spcommutation,
  duplication, spduplication,
  chol_gradient, chol_gradient!,
  kron_gradient, kron_gradient!, kronaxpy!,
  bump_diagonal!, clamp_diagonal!

"""
Vectorize the lower triangular part of a matrix.
"""
function vech(a::Union{Number, AbstractVecOrMat})
  m, n = size(a)
  out = similar(a, convert(Int, (2m - n + 1) * n / 2))
  ooffset, aoffset = 1, 1
  for j = 1:n
    len = m - j + 1 # no. elements to copy in column j
    copyto!(out, ooffset, a, aoffset, len)
    ooffset += m - j + 1
    aoffset += m + 1
  end
  out
end
# a is a scalar or (column) vector
vech(a::Union{Number, AbstractVector}) = copy(a)

"""
    commutation(type, m[, n])

Create the `mn x mn` commutation matrix `K`, defined by
`K * vec(A) = vec(A')` for any `m x n` matrix A.
"""
function commutation(t::Type, m::Integer, n::Integer)
  ((m < 0) || (n < 0)) && throw(ArgumentError("invalid Array dimensions"))
  mn = m * n
  reshape(kron(vec(Matrix{t}(I, m, m)), Matrix{t}(I, n, n)), mn, mn)
end
commutation(m::Integer, n::Integer) = commutation(Float64, m, n)
commutation(t::Type, m::Integer) = commutation(t, m, m)
commutation(m::Integer) = commutation(m, m)
commutation(M::AbstractMatrix) = commutation(eltype(M), size(M, 1), size(M, 2))

"""
    spcommutation(type, m[, n])

Create the sparse `mn`-by-`mn` commutation matrix `K`, defined by
`K * vec(A) = vec(A')` for any `m x n` matrix A.
"""
function spcommutation(t::Type, m::Integer, n::Integer)
  ((m < 0) || (n < 0)) && throw(ArgumentError("invalid Array dimensions"))
  mn = m * n
  reshape(kron(vec(sparse(t(1)I, m, m)), sparse(t(1)I, n, n)), mn, mn)
end
spcommutation(m::Integer, n::Integer) = spcommutation(Float64, m, n)
spcommutation(t::Type, m::Integer) = spcommutation(t, m, m)
spcommutation(m::Integer) = spcommutation(m, m)
spcommutation(M::AbstractMatrix) = spcommutation(eltype(M), size(M, 1), size(M, 2))

"""
    trilind(m, n,[ k])

Linear indices of the lower triangular part of an `m x n` array.
"""
function trilind(m::Integer, n::Integer, k::Integer)
  (LinearIndices(tril(trues(m, n), k)))[findall(tril(trues(m, n), k))]
end
function trilind(m::Integer, n::Integer)
  (LinearIndices(tril(trues(m, n))))[findall(tril(trues(m, n)))]
end
function trilind(m::Integer)
  (LinearIndices(tril(trues(m, m))))[findall(tril(trues(m, m)))]
end
trilind(M::AbstractArray) = trilind(size(M, 1), size(M, 2))
trilind(M::AbstractArray, k::Integer) = trilind(size(M, 1), size(M, 2), k)

"""
    triuind(m, n,[ k])

Linear indices of the upper triangular part of an `m x n` array.
"""
function triuind(m::Integer, n::Integer, k::Integer)
  (LinearIndices(triu(trues(m, n), k)))[findall(triu(trues(m, n), k))]
end
function triuind(m::Integer, n::Integer)
  (LinearIndices(triu(trues(m, n))))[findall(triu(trues(m, n)))]
end
function triuind(m::Integer)
  (LinearIndices(triu(trues(m, m))))[findall(triu(trues(m, m)))]
end
triuind(M::AbstractArray) = triuind(size(M, 1), size(M, 2))
triuind(M::AbstractArray, k::Integer) = triuind(size(M, 1), size(M, 2), k)

"""
    spduplication(type, n)

Create the sparse `n^2 x n(n+1)/2` duplication matrix, defined by
`D * vech(A) = vec(A)` for any symmetric matrix.
"""
function spduplication(t::Type, n::Integer)
  imatrix = zeros(typeof(n), n, n)
  imatrix[trilind(n, n)] = 1:binomial(n + 1, 2)
  imatrix = imatrix + copy(transpose(tril(imatrix, -1)))
  sparse(1:n^2, vec(imatrix), one(t))
end
spduplication(n::Integer) = spduplication(Float64, n)
spduplication(M::AbstractMatrix) = spduplication(eltype(M), size(M, 1))
duplication(t::Type, n::Integer) = Matrix(spduplication(t, n))
duplication(n::Integer) = duplication(Float64, n)
duplication(M::AbstractMatrix) = duplication(eltype(M), size(M, 1))

"""
    kron_gradient!(g, dM, Y)

Compute the gradient `d / d vec(X)` from a vector of derivatives `dM` where
`M=X⊗Y`, `n, q = size(X)`, and `p, r = size(Y)`.
"""
function kron_gradient!(g::VecOrMat{T}, dM::VecOrMat{T},
  Y::Matrix{T}, n::Integer, q::Integer) where {T <: Real}
  p, r = size(Y)
  mul!(g, kron(sparse(I, n * q, n * q), vec(Y)'),
    (kron(sparse(I, q, q), spcommutation(n, r), sparse(I, p, p)) * dM))
end
function kron_gradient(dM::VecOrMat{T}, Y::Matrix{T},
  n::Integer, q::Integer) where {T <: Real}
  if ndims(dM) == 1
    g = zeros(T, n * q)
  else
    g = zeros(T, n * q, size(dM, 2))
  end
  kron_gradient!(g, dM, Y, n, q)
end

"""
    chol_gradient!(g, dM, L)

Compute the gradient `d / d vech(L)` from a vector of derivatives `dM` where
`M=L*L'`.
# TODO make it more memory efficient
"""
function chol_gradient!(g::AbstractVecOrMat{T},
  dM::AbstractVecOrMat{T}, L::AbstractMatrix{T}) where {T <: Real}
  n = size(L, 1)
  mul!(g, transpose(spduplication(n)), 
    kron(L', sparse(1.0I, n, n)) * (dM + spcommutation(n) * dM))
end
function chol_gradient(dM::AbstractVecOrMat{T}, L::AbstractMatrix{T}) where {T <: Real}
  n = size(L, 1)
  if ndims(dM) == 1 # vector
    g = zeros(T, binomial(n + 1, 2))
  else # matrix
    g = zeros(T, binomial(n + 1, 2), size(dM, 2))
  end
  chol_gradient!(g, dM, L)
end

"""
    kronaxpy!(A, X, Y)

Overwrites `Y` with `A ⊗ X + Y`. Same as `Y += kron(A, X)` but more efficient.
"""
function kronaxpy!(A::AbstractVecOrMat{T},
  X::AbstractVecOrMat{T}, Y::AbstractVecOrMat{T}) where {T <: Real}

  # retrieve matrix sizes
  m, n = size(A, 1), size(A, 2)
  p, q = size(X, 1), size(X, 2)
  # loop over (i,j) blocks of Y
  irange, jrange = 1:p, 1:q
  @inbounds for j in 1:n, i in 1:m
    a = A[i, j]
    irange = ((i - 1) * p + 1):(i * p)
    jrange = ((j - 1) * q + 1):(j * q)
    Yij = view(Y, irange, jrange)  # view of (i, j)-block
    @simd for k in eachindex(Yij)
      Yij[k] += a * X[k]
    end
  end
  Y
end

"""
Add `ϵ` to the diagonal entries of matrix `A`.
"""
function bump_diagonal!(A::Matrix{T}, ϵ::T) where {T}
  @inbounds @simd for i in 1:minimum(size(A))
    A[i, i] += ϵ
  end
  A
end

"""
Clamp the diagonal entries of matrix `A` to `[lo, hi]`.
"""
function clamp_diagonal!(A::Matrix{T}, lo::T, hi::T) where {T}
  @inbounds @simd for i in 1:minimum(size(A))
    A[i, i] = clamp(A[i, i], lo, hi)
  end
  A
end

#end # module MultivariateCalculus
