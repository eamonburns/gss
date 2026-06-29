# Cascade Language (Casl)

Casl is a configuration file format inspired by the [Nix language](https://nix.dev/tutorials/nix-language.html).

A Casl file is made up of key/value pairs:

```c casl
foo = 10.0,
bar = true,
baz = "thing",
quux = {
    wow = "so cool",
},
```

A Casl file can be queried using a path:
- The path `foo` has the value `10.0`
- The path `quux.wow` has the value `"so cool"`
(Note: all paths are "absolute" at the moment. See [#3](https://github.com/eamonburns/casl/issues/3))

Paths can be used as values:
```c casl
style = {
    thumbnail = {
        left = 0.6,
        top = 0.2,
    },
    title = {
        left = 1,
        top = style.thumbnail.top,
    },
},
```
(This means that `style.thumbnail.top` and `style.title.top` are both `0.2`!)

Valid types are:
- `float` (Zig: `f64`)
- `boolean` (Zig: `bool`)
- `string` (Zig: `[]const u8`)
- `object` (Zig: `casl.Value.Object`)

## Known Issues

- Trailing commas are mandatory at the moment

## Acknowledgments

The original Casl implementation was made by Alexey Kutepov ([@rexim](https://github.com/rexim), A.K.A. [@tsoding](https://github.com/tsoding))
on a stream: [Stealing ideas from NixOS](https://youtu.be/JWIregr388Y?si=MH83rjwOyYB_5ykD)

It was written in Jai, but I don't have access to Jai, so I rewrote it in Zig
(I'm sorry Alexey, I know you hate Zig).
