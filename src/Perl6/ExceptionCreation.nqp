role ExceptionCreation {

    method ex_locprepost($pos, $orig) {
        my $prestart := $pos - 40;
        $prestart := 0 if $prestart < 0;
        my $pre   := nqp::substr($orig, $prestart, $pos - $prestart);
        $pre      := subst($pre, /.*\n/, "", :global);
        $pre      := '<BOL>' if $pre eq '';

        my $postchars := $pos + 40 > nqp::chars($orig) ?? nqp::chars($orig) - $pos !! 40;
        my $post := nqp::substr($orig, $pos, $postchars);
        $post    := subst($post, /\n.*/, "", :global);
        $post    := '<EOL>' if $post eq '';

        [$pre, $post];
    };

    method ex_find_symbol(@name, @block_stack) {
        # Make sure it's not an empty name.
        unless +@name { nqp::die("Cannot look up empty name"); }

        # GLOBAL is current view of global.
        if +@name == 1 && @name[0] eq 'GLOBAL' {
            return $*GLOBALish;
        }

        # If it's a single-part name, look through the lexical
        # scopes.
        if +@name == 1 {
            my $final_name := @name[0];
            my int $i := +@block_stack;
            while $i > 0 {
                $i := $i - 1;
                my %sym := @block_stack[$i].symbol($final_name);
                if +%sym {
                    if nqp::existskey(%sym, 'value') {
                        return %sym<value>;
                    }
                    else {
                        nqp::die("No compile-time value for $final_name");
                    }
                }
            }
        }
        
        # If it's a multi-part name, see if the containing package
        # is a lexical somewhere. Otherwise we fall back to looking
        # in GLOBALish.
        my $result := $*GLOBALish;
        if +@name >= 2 {
            my $first := @name[0];
            my int $i := +@block_stack;
            while $i > 0 {
                $i := $i - 1;
                my %sym := @block_stack[$i].symbol($first);
                if +%sym {
                    if nqp::existskey(%sym, 'value') {
                        $result := %sym<value>;
                        @name := nqp::clone(@name);
                        @name.shift();
                        $i := 0;
                    }
                    else {
                        nqp::die("No compile-time value for $first");
                    }                    
                }
            }
        }
        
        # Try to chase down the parts of the name.
        for @name {
            if nqp::existskey($result.WHO, ~$_) {
                $result := ($result.WHO){$_};
            }
            else {
                nqp::die("Could not locate compile-time value for symbol " ~
                    join('::', @name));
            }
        }
        
        $result;
    }

    method ex_typed_exception(@name, *%opts) {
        %opts<is-compile-time> := 1;

        for %opts -> $p {
            if nqp::islist($p.value) {
                my @a := [];
                for $p.value {
                    nqp::push(@a, nqp::hllizefor($_, 'perl6'));
                }
                %opts{$p.key} := nqp::hllizefor(@a, 'perl6');
            }
            else {
                %opts{$p.key} := nqp::hllizefor($p.value, 'perl6');
            }
        }
        my $file        := nqp::getlexdyn('$?FILES');
        %opts<filename> := nqp::box_s(
            (nqp::isnull($file) ?? '<unknown file>' !! $file),
            self.find_symbol(['Str'])
        );
                
        my $exsym := self.find_symbol(@name);
        my $x_comp := self.find_symbol(['X', 'Comp']);

        unless nqp::istype($exsym, $x_comp) {
            $exsym := $exsym.HOW.mixin($exsym, $x_comp);
        }

        if $exsym.HOW.name($exsym) eq 'X::Syntax::Confused' {
            my $next := nqp::substr(%opts<post>, 0, 1);
            if $next ~~ /\)|\]|\}|\»/ {
                %opts<reason> := "Unexpected closing bracket";
                %opts<highexpect> := [];
            }
            else {
                my $expected_infix := 0;
                for %opts<highexpect> {
                    if nqp::index($_, "infix") >= 0 {
                        $expected_infix := 1;
                        last;
                    }
                }
                if $expected_infix {
                    %opts<reason> := "Two terms in a row";
                }
            }
        }
        
        my $ex := $exsym.new(|%opts);

        $ex;
    };

}

