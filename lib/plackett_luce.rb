# frozen_string_literal: true

# Weng–Lin Plackett-Luce (Algorithm 4), specialized to 1-player teams.
# Matches openskill 6.x defaults:
#   mu=25, sigma=25/3, beta=25/6, kappa=1e-4, tau=25/300
#   gamma = σ / c, ordinal = μ - 3σ
#   tau is added to σ² before every match.

module PlackettLuce
  DEFAULT_MU = 25.0
  DEFAULT_SIGMA = 25.0 / 3.0
  BETA = 25.0 / 6.0
  KAPPA = 0.0001
  TAU = 25.0 / 300.0
  BETA2 = BETA * BETA
  TAU2 = TAU * TAU

  Rating = Struct.new(:mu, :sigma, :name, keyword_init: true) do
    def ordinal(z = 3.0)
      mu - z * sigma
    end
  end

  module_function

  def rating(mu: DEFAULT_MU, sigma: DEFAULT_SIGMA, name: nil)
    Rating.new(mu: mu.to_f, sigma: sigma.to_f, name: name)
  end

  # Mutate parallel mu/sigma arrays in place. Callers MUST pass players
  # already ordered best → worst (unique ranks 0..n-1). n may be < 2 (no-op).
  def update_sorted!(mu, sigma)
    n = mu.size
    return if n < 2

    n.times { |i| sigma[i] = Math.sqrt(sigma[i] * sigma[i] + TAU2) }

    sigma2 = Array.new(n) { |i| sigma[i] * sigma[i] }
    c = Math.sqrt(sigma2.sum { |s| s + BETA2 })
    inv_c = 1.0 / c
    exp_mu = Array.new(n) { |i| Math.exp(mu[i] * inv_c) }

    # sum_q[q] = exp_mu[q] + ... + exp_mu[n-1]
    sum_q = Array.new(n)
    acc = 0.0
    (n - 1).downto(0) do |q|
      acc += exp_mu[q]
      sum_q[q] = acc
    end

    n.times do |i|
      omega = 0.0
      delta = 0.0
      ei = exp_mu[i]
      (0..i).each do |q|
        frac = ei / sum_q[q]
        omf = 1.0 - frac
        delta += frac * omf
        omega += (q == i) ? omf : -frac
      end
      s2 = sigma2[i]
      omega *= s2 * inv_c
      delta *= s2 * inv_c * inv_c
      delta *= sigma[i] * inv_c # gamma = σ / c
      mu[i] += omega
      sigma[i] *= Math.sqrt([1.0 - delta, KAPPA].max)
    end
  end

  # ratings: Array<Rating>, ranks: Array<Numeric> (lower = better).
  # Returns new Rating objects in the same order as `ratings`.
  def rate(ratings, ranks:)
    n = ratings.size
    raise ArgumentError, "ratings and ranks must be the same length" unless ranks.size == n
    raise ArgumentError, "need at least 2 ratings" if n < 2

    order = (0...n).sort_by { |i| ranks[i] }
    mu = order.map { |i| ratings[i].mu }
    sigma = order.map { |i| ratings[i].sigma }
    sorted_ranks = order.map { |i| ranks[i].to_i }

    if sorted_ranks.each_cons(2).all? { |a, b| a < b }
      update_sorted!(mu, sigma)
    else
      update_tied!(mu, sigma, sorted_ranks)
    end

    out = Array.new(n)
    order.each_with_index do |orig, j|
      out[orig] = rating(mu: mu[j], sigma: sigma[j], name: ratings[orig].name)
    end
    out
  end

  # General path: non-unique ranks (ties). Applies tau, then Algorithm 4.
  def update_tied!(mu, sigma, ranks)
    n = mu.size
    n.times { |i| sigma[i] = Math.sqrt(sigma[i] * sigma[i] + TAU2) }

    sigma2 = Array.new(n) { |i| sigma[i] * sigma[i] }
    c = Math.sqrt(sigma2.sum { |s| s + BETA2 })
    inv_c = 1.0 / c
    exp_mu = Array.new(n) { |i| Math.exp(mu[i] * inv_c) }

    sum_q = Array.new(n, 0.0)
    n.times do |q|
      s = 0.0
      n.times { |i| s += exp_mu[i] if ranks[i] >= ranks[q] }
      sum_q[q] = s
    end

    counts = Hash.new(0)
    ranks.each { |r| counts[r] += 1 }

    old_mu = mu.dup
    n.times do |i|
      omega = 0.0
      delta = 0.0
      ei = exp_mu[i]
      n.times do |q|
        next if ranks[q] > ranks[i]
        aq = counts[ranks[q]]
        frac = ei / sum_q[q]
        omf = 1.0 - frac
        delta += frac * omf / aq
        omega += (ranks[q] == ranks[i]) ? (omf / aq) : (-frac / aq)
      end
      s2 = sigma2[i]
      omega *= s2 * inv_c
      delta *= s2 * inv_c * inv_c
      delta *= sigma[i] * inv_c
      mu[i] += omega
      sigma[i] *= Math.sqrt([1.0 - delta, KAPPA].max)
    end

    rank_groups = Hash.new { |h, k| h[k] = [] }
    ranks.each_with_index { |r, i| rank_groups[r] << i }
    rank_groups.each_value do |indices|
      next if indices.size <= 1
      avg = indices.sum { |i| mu[i] - old_mu[i] } / indices.size.to_f
      indices.each { |i| mu[i] = old_mu[i] + avg }
    end
  end
end
