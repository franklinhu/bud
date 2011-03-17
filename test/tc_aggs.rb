require 'test_common'

class ShortestPaths
  include Bud

  state {
    table :link, [:from, :to, :cost]
    table :path, [:from, :to, :next, :cost]
    table :shortest, [:from, :to] => [:next, :cost]
    table :minmaxsumcntavg, [:from, :to] => [:mincost, :maxcost, :sumcost, :cnt, :avgcost]
    table :avrg, [:from, :to] => [:ave, :some, :kount]
    table :avrg2, [:from, :to] => [:ave, :some, :kount]
  }

  bootstrap do
    link << ['a', 'b', 1]
    link << ['a', 'b', 4]
    link << ['b', 'c', 1]
    link << ['c', 'd', 1]
    link << ['d', 'e', 1]
  end

  declare
  def program
    path <= link.map{|e| [e.from, e.to, e.to, e.cost]}

    j = join [link, path], [path.from, link.to]
    path <= j.map do |l,p|
      [l.from, p.to, p.from, l.cost+p.cost] # if l.to == p.from
    end

    # second stratum
    shortest <= path.argmin([path.from, path.to], path.cost)
    minmaxsumcntavg <= path.group([path.from, path.to], min(path.cost), max(path.cost), sum(path.cost), count, avg(path.cost))
    avrg <= path.group([:from, :to], min(:cost), max(path.cost), sum(:cost), count, avg(:cost)) do |t|
      [t[0], t[1], t[6], t[4], t[5]]
    end
    avrg2 <= path.group([:from, :to], min(:cost), max(path.cost), sum(:cost), count, avg(:cost)).rename([:from, :to] => [:mincol, :maxcol, :sumcol, :cntcol, :avgcol]).map do |t|
        [t.from, t.to, t.avgcol, t.sumcol, t.cntcol]
    end
  end
end

class TiedPaths
  include Bud

  state {
    table :link, [:from, :to, :cost]
    table :path, [:from, :to, :next, :cost]
    table :shortest, [:from, :to] => [:next, :cost]
  }

  bootstrap do
    link << ['a', 'b', 1]
    link << ['a', 'b', 4]
    link << ['b', 'c', 1]
    link << ['a', 'c', 2]
  end

  declare
  def program
    path <= link.map{|e| [e.from, e.to, e.to, e.cost]}
    path <= join ([link, path], [path.from, link.to]).map do |l,p|
      [l.from, p.to, p.from, l.cost+p.cost] # if l.to == p.from
    end
    shortest <= path.argmin([path.from, path.to], path.cost).argagg(:max, [:from, :to], :next)
  end
end

class PriorityQ
  include Bud

  state {
    table :q, [:item] => [:priority]
    scratch :out, [:item] => [:priority]
    scratch :minny, [:priority]
    scratch :out2, [:item] => [:priority]
  }

  bootstrap do
    q << ['c', 2]
    q << ['d', 3]
    q << ['a', 1]
    q << ['b', 2]
  end

  declare
  def program
    # second stratum
    out <= q.argagg(:min, [], q.priority)
    minny <= q.group(nil, min(q.priority))
    q <- out

    # third stratum
    out2 <= natjoin([q, minny]).map{|q, m| q}
  end
end

class DupAggs
  include Bud

  state {
    table :tab, [:i]
#    scratch :out, [:s1, :s2]
  }

  bootstrap do
    tab << [1]
    tab << [2]
  end

  declare
  def prog
    out = tab.group(nil, sum(tab.i), sum(tab.i))
    p out.inspect
  end
end

class Rename
  include Bud

  state {
    table :emp, [:ename, :dname] => [:sal]
    table :shoes, [:dname] => [:usualsal]
  }

  bootstrap do
    emp << ['joe', 'shoe', 10]
    emp << ['joe', 'toy', 5]
    emp << ['bob', 'shoe', 11]
  end

  declare
  def rules
    shoes <= emp.group([:dname], avg(:sal)).rename([:dept] => [:avgsal]).map{|t| t if t.dept == 'shoe'}
  end
end

class JoinAgg < Rename
  state {
    scratch :richsal, [:sal]
    scratch :rich, emp.key_cols => emp.val_cols
    scratch :argrich, emp.key_cols => emp.val_cols
  }

  declare
  def rules
    richsal <= emp.group([], max(:sal))
    rich <= natjoin([richsal, emp]).map{|r,e| e}
    argrich <= emp.argmax([], emp.sal)
  end
end

class AggJoin
  include Bud
  state do
    table :shoes, [:dname] => [:usualsal]
    table :emp, [:ename, :dname] => [:sal]
    scratch :funny, [:dname] => [:max_sal, :usual_sal]
  end
  
  bootstrap do
    emp << ['joe', 'shoe', 10]
    emp << ['joe', 'toy', 5]
    emp << ['bob', 'shoe', 11]
    shoes << ['shoe', 9]
  end

  declare
  def rules
    funny <= natjoin([emp, shoes]).flatten.group([:dname], max(:sal), max(:usualsal))
  end
end

class ChoiceAgg
  include Bud
  
  state do
    scratch :t1
    scratch :t2
  end
  
  declare
  def rules
    t1 <= [[1,1],[2,1]]
    t2 <= t1.argagg(:choose, [], :key)    
  end
end

class TestAggs < Test::Unit::TestCase
  def test_paths
    program = ShortestPaths.new
    assert_nothing_raised(RuntimeError) { program.tick }

    program.minmaxsumcntavg.each do |t|
      assert(t[4])
      assert(t[2] <= t[3])
      assert_equal(t[4]*1.0 / t[5], t[6])
    end
    program.avrg.each do |t|
      assert_equal(t.some*1.0 / t.kount, t.ave)
    end
    program.avrg2.each do |t|
      assert_equal(t.some*1.0 / t.kount, t.ave)
    end
    program.shortest.each do |t|
      assert_equal(t[1][0] - t[0][0], t[3])
    end
    shorts = program.shortest.map {|s| [s.from, s.to, s.cost]}
    costs = program.minmaxsumcntavg.map {|c| [c.from, c.to, c.mincost]}
    assert_equal([], shorts - costs)
  end
  
  def test_tied_paths
    program = TiedPaths.new
    assert_nothing_raised(RuntimeError) { program.tick }
    assert_equal([["a", "c", "c", 2], ["b", "c", "c", 1], ["a", "b", "b", 1]].sort, program.shortest.to_a.sort)
  end

  def test_non_exemplary
    program = ShortestPaths.new
    assert_nothing_raised(RuntimeError) { program.tick }
    assert_raise(Bud::BudError) {p = program.path.argagg(:count, [program.path.from, program.path.to], nil)}
    assert_raise(Bud::BudError) {p = program.path.argagg(:sum, [program.path.from, program.path.to], program.path.cost)}
    assert_raise(Bud::BudError) {p = program.path.argagg(:avg, [program.path.from, program.path.to], program.path.cost)}
  end

  def test_argaggs
    program = PriorityQ.new
    assert_nothing_raised (RuntimeError) { program.tick }
    argouts = program.out.to_a
    basicouts = program.out2.to_a
    assert_equal([], argouts - basicouts)
  end

  def test_rename
    program = Rename.new
    assert_nothing_raised (RuntimeError) { program.tick }
    shoes = program.shoes.to_a
    assert_equal([["shoe", 10.5]], shoes)
  end

  def test_join_agg
    program = JoinAgg.new
    assert_nothing_raised (RuntimeError) { program.tick }
    rich = program.rich.first
    assert_equal(['bob', 'shoe', 11], rich)
    argrich = program.argrich.first
    assert_equal(['bob', 'shoe', 11], argrich)
  end

  def test_agg_join
    p = AggJoin.new
    assert_nothing_raised (RuntimeError) { p.tick }
    assert_equal([['shoe', 11, 9]], p.funny.to_a  )
  end
  
  def test_choice_agg
    p = ChoiceAgg.new
    assert_nothing_raised {p.tick}
    assert(([[1,1]]) == p.t2.to_a || ([[2,1]]) == p.t2.to_a)
  end
end
