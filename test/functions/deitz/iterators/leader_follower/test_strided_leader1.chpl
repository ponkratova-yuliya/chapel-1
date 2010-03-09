def foo(n: int) {
  for i in 1..n do
    yield i;
}

def foo(param tag: iterator, n: int) where tag == iterator.leader {
  cobegin {
    on Locales(0) do yield tuple(0..n-1 by 2);
    on Locales(1) do yield tuple(1..n-1 by 2);
  }
}

def foo(param tag: iterator, follower, n: int) where tag == iterator.follower {
  for i in follower(1)+1 do
    yield i;
}

config var n: int = 8;

var A: [1..n] int;

forall i in foo(n) do
  A(i) = here.id * 100 + i;

writeln(A);

use Random;

{
  var B: [1..n] real;

  var rs = new RandomStream(seed=315);

  forall (i, r) in ([1..n], rs.iterate([1..n])) do
    B(i) = r;

  writeln(B);
}

{
  var B: [1..n] real;

  var rs = new RandomStream(seed=315);

  forall (f, r) in (foo(n), rs.iterate([1..n])) do
    B(f) = r;

  writeln(B);
}
