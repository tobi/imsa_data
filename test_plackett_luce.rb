#!/usr/bin/env ruby
# frozen_string_literal: true

# Golden vectors captured from openskill 6.1.3 PlackettLuce with default
# hyperparameters. If these drift, ratings in driver_elo.csv will too.

require "minitest/autorun"
require_relative "lib/plackett_luce"

class TestPlackettLuce < Minitest::Test
  EPS = 1e-10

  def close!(expected, actual, msg = nil)
    assert_in_delta expected, actual, EPS, msg || "expected #{expected} got #{actual}"
  end

  def rate(mus_sigmas, ranks)
    ratings = mus_sigmas.map { |mu, sigma, name| PlackettLuce.rating(mu: mu, sigma: sigma, name: name) }
    PlackettLuce.rate(ratings, ranks: ranks)
  end

  def test_defaults
    r = PlackettLuce.rating
    close! 25.0, r.mu
    close! 25.0 / 3.0, r.sigma
    close! 0.0, r.ordinal
  end

  def test_two_player_defaults
    a, b = rate([[25.0, 25.0 / 3.0, "a"], [25.0, 25.0 / 3.0, "b"]], [0, 1])
    close! 27.6353894931404973, a.mu
    close! 8.0659014135436795, a.sigma
    close! 22.3646105068595027, b.mu
    close! 8.0659014135436795, b.sigma
  end

  def test_three_player_mixed_mu
    a, b, c = rate(
      [[25.0, 25.0 / 3.0, "a"], [25.0, 25.0 / 3.0, "b"], [28.0, 25.0 / 3.0, "c"]],
      [0, 1, 2]
    )
    close! 27.9605098181942786, a.mu
    close! 8.2096341208410895, a.sigma
    close! 26.0081533253119304, b.mu
    close! 8.0639686067081620, b.sigma
    close! 24.0313368564937910, c.mu
    close! 8.0521604454447608, c.sigma
    close! 3.3316074556710085, a.ordinal
    close! 1.8162475051874445, b.ordinal
    close!(-0.1251444798404897, c.ordinal)
  end

  def test_five_player_mixed
    rs = (0...5).map { |i| [22.0 + i, 8.0, i.to_s] }
    out = rate(rs, (0...5).to_a)
    expected = [
      [24.5999850050562330, 7.9633957427452415],
      [24.8354984919847190, 7.9171645547492453],
      [24.7617113810018843, 7.8592970923122163],
      [24.0917941295903582, 7.7909826040869001],
      [21.7110109923668020, 7.7864644829674630]
    ]
    expected.each_with_index do |(mu, sigma), i|
      close! mu, out[i].mu, "mix #{i} mu"
      close! sigma, out[i].sigma, "mix #{i} sigma"
    end
  end

  def test_unwind_preserves_input_order
    # ranks [1,0,2] → b wins, a second, c last. Output order must stay a,b,c.
    a, b, c = rate(
      [[25.0, 25.0 / 3.0, "a"], [31.0, 25.0 / 3.0, "b"], [22.0, 25.0 / 3.0, "c"]],
      [1, 0, 2]
    )
    assert_equal "a", a.name
    assert_equal "b", b.name
    assert_equal "c", c.name
    close! 25.6405677998315902, a.mu
    close! 8.0656194397320924, a.sigma
    close! 33.4010457399474276, b.mu
    close! 8.1909969985809781, b.sigma
    close! 18.9583864602209857, c.mu
    close! 8.0791613281271424, c.sigma
  end

  def test_ten_player_defaults
    out = rate((0...10).map { |i| [25.0, 25.0 / 3.0, i.to_s] }, (0...10).to_a)
    expected = [
      [27.1214476193863128, 8.3252597045238907],
      [26.8595405058818315, 8.3159325435185671],
      [26.5648950031892852, 8.3055912188160210],
      [26.2281572858263807, 8.2939984610646178],
      [25.8352966155696535, 8.2808296243015818],
      [25.3638638112615844, 8.2656331177988687],
      [24.7745728058764989, 8.2477890801548011],
      [23.9888514653630480, 8.2265904712724218],
      [22.8102694545928770, 8.2026765517270839],
      [20.4531054330525279, 8.2026765517270839]
    ]
    expected.each_with_index do |(mu, sigma), i|
      close! mu, out[i].mu, "ten #{i} mu"
      close! sigma, out[i].sigma, "ten #{i} sigma"
    end
  end

  def test_does_not_mutate_inputs
    r = PlackettLuce.rating(mu: 25.0, sigma: 25.0 / 3.0, name: "a")
    other = PlackettLuce.rating(mu: 25.0, sigma: 25.0 / 3.0, name: "b")
    PlackettLuce.rate([r, other], ranks: [0, 1])
    close! 25.0, r.mu
    close! 25.0 / 3.0, r.sigma
  end
end
