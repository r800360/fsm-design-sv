"""
vending_bounds.py - exhaustive analysis of the vending machine's till (every possible customer behaviour):
  * smallest initial deposit and counter widths that never shortchange a customer (fixed-deposit variant)
  * proof that the lock rules of the zero-deposit variant are sufficient and necessary
"""
from collections import deque

VAL = {1: 1, 3: 3, 5: 5}


def pay(owed, n1, n3):
    """change-serializer policy (rtl/change_serializer.sv); returns new (n1, n3) or None if the till cannot pay."""
    while owed:
        if owed == 3 and n3 > 0:
            n3 -= 1
            owed = 0
        elif n1 > 0:
            n1 -= 1
            owed -= 1
        else:
            return None
    return n1, n3


def step(state, action):
    b, n1, n3, n5, bars = state
    if bars == 0:
        return state                   # EMPTY: slots closed
    if action == "refund":
        r = pay(b, n1, n3)
        return None if r is None else (0, r[0], r[1], n5, bars)
    if action == 5 and b == 3 and bars == 1:
        return state                   # LOCK_5 (last bar)
    n1 += action == 1
    n3 += action == 3
    n5 += action == 5
    t = b + VAL[action]
    if t < 4:
        return (t, n1, n3, n5, bars)
    if t == 8:
        return (0, n1, n3, n5, bars - 2)
    r = pay(t - 4, n1, n3)
    return None if r is None else (0, r[0], r[1], n5, bars - 1)


def explore(n1, n3, bars=15):
    start = (0, n1, n3, 0, bars)
    seen = {start}
    q = deque([start])
    mx = [n1, n3, 0]
    while q:
        s = q.popleft()
        for a in (1, 3, 5, "refund"):
            t = step(s, a)
            if t is None:
                return False, None, s, a
            if t not in seen:
                seen.add(t)
                q.append(t)
                mx = [max(mx[0], t[1]), max(mx[1], t[2]), max(mx[2], t[3])]
    return True, (mx, len(seen)), None, None


if __name__ == "__main__":
    best = None
    for total in range(0, 61):
        for n3 in range(0, total // 3 + 1):
            n1 = total - 3 * n3
            ok, info, bad, act = explore(n1, n3)
            if ok and (best is None or (n1 + 3 * n3, n1 + n3) < (best[0] + 3 * best[1], best[0] + best[1])):
                best = (n1, n3, info)
        if best:
            break
    n1, n3, (mx, nstates) = best
    print(f"minimal initial deposit: {n1} 1-bills + {n3} 3-bills (= {n1 + 3 * n3}), {nstates} reachable states")
    ok, info, bad, act = explore(n1 - 1, n3)
    print(f"with one 1-bill less the machine can be forced to shortchange: state {bad} (balance, n1, n3, n5, bars), action {act}")
    for alt in ((n1 - 3, n3 + 1), (n1 - 2, n3 + 1)):
        if alt[0] >= 0:
            ok2, _, bad2, act2 = explore(*alt)
            print(f"  alternative {alt[0]} 1-bills + {alt[1]} 3-bills: {'safe' if ok2 else f'unsafe ({bad2}, {act2})'}")
    import math
    for name, m in zip(("1-bills", "3-bills", "5-bills"), mx):
        print(f"  {name} counter: maximum reachable value {m} -> {max(1, math.ceil(math.log2(m + 1)))} bits")


# ---------------------------------------------------------------------------------------------------------------
# zero-deposit till with slot locks (vending_machine LOCKS = 1): the lock rules are sufficient and necessary.
def vm4_locks(b, n1, n3, bars):
    lock5 = [n1 < 1, n1 < 2, n1 < 3 and n3 == 0, bars == 1][b]
    lock3 = b == 3 and n1 < 2
    return lock3, lock5


def vm4_step(state, action):
    """like step(), but without the built-in last-bar lock; returns None on shortchange or on owing 2 bars at 1."""
    b, n1, n3, n5, bars = state
    if action == "refund":
        r = pay(b, n1, n3)
        return None if r is None else (0, r[0], r[1], n5, bars)
    n1 += action == 1
    n3 += action == 3
    n5 += action == 5
    t = b + VAL[action]
    if t < 4:
        return (t, n1, n3, n5, bars)
    if t == 8:
        return None if bars < 2 else (0, n1, n3, n5, bars - 2)
    r = pay(t - 4, n1, n3)
    return None if r is None else (0, r[0], r[1], n5, bars - 1)


def verify_vm4(bars=15):
    start = (0, 0, 0, 0, bars)
    seen, q = {start}, deque([start])
    necessary = {"lock3": 0, "lock5": 0}
    while q:
        s = q.popleft()
        b, n1, n3, n5, nb = s
        if nb == 0:
            continue                                   # EMPTY: all slots closed
        l3, l5 = vm4_locks(b, n1, n3, nb)
        for a in (1, 3, 5, "refund"):
            t = vm4_step(s, a)
            locked = (a == 3 and l3) or (a == 5 and l5)
            if locked:
                assert t is None, f"lock not necessary: state {s} action {a}"
                necessary["lock3" if a == 3 else "lock5"] += 1
                continue
            assert t is not None, f"shortchange reachable: state {s} action {a}"
            if t not in seen:
                seen.add(t)
                q.append(t)
    return len(seen), necessary


if __name__ == "__main__":
    n, nec = verify_vm4()
    print(f"\nzero-deposit locks: {n} reachable states from an empty till; no shortchange reachable (sufficient);"
          f" every raised lock blocks a bill that would shortchange or over-dispense (necessary):"
          f" {nec['lock5']} LOCK_5 and {nec['lock3']} LOCK_3 state/bill pairs checked")
