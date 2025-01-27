(*
 * Copyright (c) 2015, Théo Laurent <theo.laurent@ens.fr>
 * Copyright (c) 2015, KC Sivaramakrishnan <sk826@cl.cam.ac.uk>
 * Copyright (c) 2023, Vesa Karvonen <vesa.a.j.k@gmail.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

(* Michael-Scott queue *)

type 'a node = Nil | Next of 'a * 'a node Atomic.t

type 'a t = {
  head : 'a node Atomic.t Atomic.t;
  tail : 'a node Atomic.t Atomic.t;
}

let create () =
  let next = Atomic.make Nil in
  { head = Atomic.make next; tail = Atomic.make next }

let is_empty { head; _ } = Atomic.get (Atomic.get head) == Nil

let pop { head; _ } =
  let b = Backoff.create () in
  let rec loop () =
    let old_head = Atomic.get head in
    match Atomic.get old_head with
    | Nil -> None
    | Next (value, next) when Atomic.compare_and_set head old_head next ->
        Some value
    | _ ->
        Backoff.once b;
        loop ()
  in
  loop ()

let rec fix_tail tail old_tail new_tail =
  if Atomic.compare_and_set tail old_tail new_tail then
    match Atomic.get new_tail with
    | Nil -> ()
    | Next (_, new_new_tail) -> fix_tail tail new_tail new_new_tail

let push { tail; _ } value =
  let rec find_tail_and_enq curr_end node =
    if not (Atomic.compare_and_set curr_end Nil node) then
      match Atomic.get curr_end with
      | Nil -> find_tail_and_enq curr_end node
      | Next (_, n) -> find_tail_and_enq n node
  in
  let new_tail = Atomic.make Nil in
  let newnode = Next (value, new_tail) in
  let old_tail = Atomic.get tail in
  find_tail_and_enq old_tail newnode;
  if Atomic.compare_and_set tail old_tail new_tail then
    match Atomic.get new_tail with
    | Nil -> ()
    | Next (_, new_new_tail) -> fix_tail tail new_tail new_new_tail

let clean_until { head; _ } f =
  let b = Backoff.create () in
  let rec loop () =
    let old_head = Atomic.get head in
    match Atomic.get old_head with
    | Nil -> ()
    | Next (value, next) ->
        if not (f value) then
          if Atomic.compare_and_set head old_head next then (
            Backoff.reset b;
            loop ())
          else (
            Backoff.once b;
            loop ())
        else ()
  in
  loop ()

type 'a cursor = 'a node

let snapshot { head; _ } = Atomic.get (Atomic.get head)
let next = function Nil -> None | Next (a, n) -> Some (a, Atomic.get n)
