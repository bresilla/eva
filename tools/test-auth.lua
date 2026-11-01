local sessions, opened, failures, busy = {}, 0, 0, false
package.preload.morf = function() return {
  env=function() return '/never-connect-this-mock' end,
  greetd={converse=function(user)
    local login={user=user,answers={},cancelled=0,starts=0}
    function login:on_message(fn) self.emit=fn end
    function login:respond(answer) self.answers[#self.answers+1]=answer or '<ack>' end
    function login:cancel() self.cancelled=self.cancelled+1 end
    function login:start() self.starts=self.starts+1 end
    sessions[#sessions+1]=login
    return login
  end},
} end
local auth=dofile('lib/shell/auth/init.lua')
local function door(opts)
  opts=opts or {}
  opts.user='test-user';opts.session={command={'true'},environment={}}
  opts.on_busy=function(value) busy=value end
  opts.on_failed=function() failures=failures+1 end
  opts.on_open=function() opened=opened+1 end
  return auth.greeter(opts)
end
local d=door()
assert(#sessions==0,'startup must not authenticate')
d:switch('another-user'); assert(#sessions==0,'account selection must not authenticate')
d:submit('');d:submit(nil);assert(#sessions==0,'empty submission must not authenticate')
d:submit('test-answer');assert(#sessions==1 and busy)
d:submit('duplicate');assert(#sessions==1,'duplicate submit')
local first=sessions[1]
first.emit{kind='auth',auth_type='secret'};assert(first.answers[1]=='test-answer')
first.emit{kind='error',text='Account locked'}
assert(#sessions==1 and failures==1 and not busy,'error must not retry')
assert(d.held==nil and d.login==nil,'clear held secret')
first.emit{kind='success'};assert(opened==0 and first.starts==0,'stale callback')
d:submit('next-answer');assert(#sessions==2,'explicit retry allowed')
local second=sessions[2]
second.emit{kind='auth',auth_type='info',text='Please wait'}
second.emit{kind='auth',auth_type='secret'}
assert(second.answers[1]=='<ack>' and second.answers[2]=='next-answer')
second.emit{kind='success'};assert(second.starts==1)
second.emit{kind='success'};assert(opened==1)
local preview=door{enabled=false};preview:submit('answer')
assert(#sessions==2,'preview must never connect even with GREETD_SOCK')
local stopped=door();stopped:submit('answer');local third=sessions[3]
stopped:switch('other');third.emit{kind='success'}
assert(#sessions==3 and third.starts==0 and not busy,'switch must cancel without retry')
print('PASS: startup, account switching, empty/duplicate submit, failure, explicit retry, stale callbacks, successful login, preview isolation')

local disconnected=door();disconnected:submit('answer')
local last=sessions[#sessions];local count=#sessions
last.emit{kind='failed',text='connection lost'}
assert(not busy and disconnected.held==nil and disconnected.login==nil)
assert(#sessions==count,'transport error must stop without retrying')
print('PASS: transport failure releases busy state without retrying')

-- A stack that asks twice: the second question reaches the person, and their
-- answer goes to the same conversation.
local prompts={}
local asked=auth.greeter{user='test-user',session={command={'true'},environment={}},
  on_busy=function(value) busy=value end,on_prompt=function(text) prompts[#prompts+1]=text end,
  on_failed=function() failures=failures+1 end,on_open=function() opened=opened+1 end}
asked:submit('password')
local twice=sessions[#sessions]
twice.emit{kind='auth',auth_type='secret',text='Password:'}
assert(twice.answers[1]=='password' and busy,'the password goes first')
twice.emit{kind='auth',auth_type='visible',text='Verification code:'}
assert(prompts[1]=='Verification code:' and not busy,'the second question is shown')
asked:submit('123456')
assert(twice.answers[2]=='123456' and busy,'the answer continues the conversation')
print('PASS: a second question reaches the person and continues the conversation')

-- greetd refusing the conversation still gives an answer, and a later try can
-- reach it.
local refused=door()
local converse=package.loaded.morf.greetd.converse
package.loaded.morf.greetd.converse=function() error('socket refused') end
local before=failures
busy=false
refused:submit('answer')
assert(failures==before+1,'a refused conversation is reported')
assert(not busy,'a refused conversation leaves nothing busy')
package.loaded.morf.greetd.converse=converse
refused:submit('answer')
assert(refused.login~=nil,'a later try reaches greetd again')
print('PASS: a refused conversation is reported and can be retried')
